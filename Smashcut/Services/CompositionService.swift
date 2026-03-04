import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import Foundation
import UIKit
import Vision

// MARK: - Video Frame Reader

/// Reads video frames sequentially from an AVAssetReader, tracking the current
/// frame for compositing at arbitrary segment times.
private final class VideoFrameReader {
    let layer: Layer
    let reader: AVAssetReader
    let output: AVAssetReaderTrackOutput
    let effectiveDuration: Double

    private var currentSampleBuffer: CMSampleBuffer?
    private(set) var currentImage: CIImage?
    private(set) var currentPixelBuffer: CVPixelBuffer?
    private(set) var isExhausted = false

    init(layer: Layer, reader: AVAssetReader, output: AVAssetReaderTrackOutput, assetDuration: Double) {
        self.layer = layer
        self.reader = reader
        self.output = output
        let trimStart = layer.trimStartSeconds ?? 0
        let trimEnd = layer.trimEndSeconds ?? assetDuration
        self.effectiveDuration = trimEnd - trimStart
    }

    /// Advances the reader to the frame at or just past the given segment time.
    func advance(to segmentTime: CMTime) {
        guard !isExhausted else { return }
        let trimStart = layer.trimStartSeconds ?? 0
        let targetPTS = CMTimeAdd(segmentTime, CMTime(seconds: trimStart, preferredTimescale: 600))

        while let next = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(next)
            if let ib = CMSampleBufferGetImageBuffer(next) {
                currentPixelBuffer = ib
                currentImage = CIImage(cvPixelBuffer: ib)
                currentSampleBuffer = next
            }
            if pts >= targetPTS { break }
        }
        if reader.status == .completed {
            isExhausted = true
        }
    }
}

// MARK: - CompositionService

actor CompositionService {
    static let shared = CompositionService()

    enum CompositionError: LocalizedError {
        case exportFailed(String)
        case invalidAsset
        case writerSetupFailed

        var errorDescription: String? {
            switch self {
            case .exportFailed(let msg): return "Export failed: \(msg)"
            case .invalidAsset: return "Invalid video asset"
            case .writerSetupFailed: return "Failed to set up video writer"
            }
        }
    }

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - N-Layer Composition

    /// Composites all layers in a TimelineSegment into a single exported MP4.
    ///
    /// Layers are sorted by zIndex and composited bottom-to-top. Video layers
    /// are read frame-by-frame via AVAssetReader. Photo layers are composited as
    /// static images for their time range. Text layers are rendered per-frame
    /// using their CaptionStyle. Audio from video layers is mixed using
    /// AVMutableAudioMix with per-layer volume.
    func compose(
        segment: TimelineSegment,
        outputURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        let allLayers = segment.layers.sorted { $0.zIndex < $1.zIndex }
        let videoLayers = allLayers.filter { $0.type == .video }

        // Determine output size from first video layer's natural size
        let outputSize: CGSize
        if let firstVideo = videoLayers.first, let url = firstVideo.sourceURL {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw CompositionError.invalidAsset
            }
            outputSize = try await track.load(.naturalSize)
        } else {
            outputSize = CGSize(width: 1080, height: 1920)
        }

        // Calculate total duration if not set on the segment
        var totalSeconds = segment.duration
        if totalSeconds <= 0 {
            totalSeconds = try await inferDuration(layers: allLayers, textLayers: segment.textLayers)
        }
        guard totalSeconds > 0 else { throw CompositionError.invalidAsset }

        let fps: Int32 = 30
        let frameDuration = CMTime(value: 1, timescale: fps)
        let endTime = CMTime(seconds: totalSeconds, preferredTimescale: 600)
        let canvasRect = CGRect(origin: .zero, size: outputSize)
        let totalFrames = max(1.0, totalSeconds * Double(fps))

        // Set up frame readers for each video layer
        var frameReaders: [UUID: VideoFrameReader] = [:]
        for layer in videoLayers {
            guard let url = layer.sourceURL else { continue }
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { continue }

            let reader = try AVAssetReader(asset: asset)
            let assetDuration = try await asset.load(.duration).seconds
            let trimStart = layer.trimStartSeconds ?? 0
            let trimEnd = layer.trimEndSeconds ?? assetDuration
            reader.timeRange = CMTimeRange(
                start: CMTime(seconds: trimStart, preferredTimescale: 600),
                end: CMTime(seconds: trimEnd, preferredTimescale: 600)
            )

            let output = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            )
            output.alwaysCopiesSampleData = false
            reader.add(output)
            frameReaders[layer.id] = VideoFrameReader(
                layer: layer, reader: reader, output: output, assetDuration: assetDuration
            )
        }

        // Pre-load CIImages for photo layers
        var photoImages: [UUID: CIImage] = [:]
        for layer in allLayers where layer.type == .photo {
            guard let url = layer.sourceURL,
                  let uiImage = UIImage(contentsOfFile: url.path),
                  let ci = CIImage(image: uiImage) else { continue }
            photoImages[layer.id] = ci
        }

        // Segmentation request (reused across all frames for bg-removal layers)
        let segRequest = VNGeneratePersonSegmentationRequest()
        segRequest.qualityLevel = .balanced
        segRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8

        // Set up AVAssetWriter (video-only; audio is mixed in a second pass)
        let tempVideoURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent("comp_temp_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: tempVideoURL)

        let writer = try AVAssetWriter(outputURL: tempVideoURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(outputSize.width),
                kCVPixelBufferHeightKey as String: Int(outputSize.height),
            ]
        )
        writer.add(writerInput)

        // Start all readers
        for (_, frameReader) in frameReaders {
            guard frameReader.reader.startReading() else {
                throw CompositionError.invalidAsset
            }
        }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Pre-sort text layers by zIndex
        let sortedTextLayers = segment.textLayers.sorted { $0.layer.zIndex < $1.layer.zIndex }

        // Frame-by-frame compositing loop
        var currentTime = CMTime.zero
        var frameCount = 0

        while currentTime < endTime {
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }

            var canvas = CIImage(color: CIColor.black).cropped(to: canvasRect)

            // Composite media layers in zIndex order
            for layer in allLayers {
                switch layer.type {
                case .video:
                    guard let reader = frameReaders[layer.id] else { continue }
                    guard currentTime.seconds < reader.effectiveDuration else { continue }
                    reader.advance(to: currentTime)
                    guard var frame = reader.currentImage else { continue }

                    if layer.hasBackgroundRemoval, let pb = reader.currentPixelBuffer {
                        frame = removeBackground(pixelBuffer: pb, frame: frame, request: segRequest)
                    }
                    if layer.filter != .none {
                        frame = applyFilterPreset(frame, preset: layer.filter)
                    }
                    canvas = compositeLayerImage(frame, onto: canvas, at: layer.position, canvasSize: outputSize)

                case .photo:
                    let seconds = currentTime.seconds
                    if let trimStart = layer.trimStartSeconds, seconds < trimStart { continue }
                    if let trimEnd = layer.trimEndSeconds, seconds >= trimEnd { continue }
                    guard var photo = photoImages[layer.id] else { continue }

                    if layer.filter != .none {
                        photo = applyFilterPreset(photo, preset: layer.filter)
                    }
                    canvas = compositeLayerImage(photo, onto: canvas, at: layer.position, canvasSize: outputSize)

                case .text:
                    break
                }
            }

            // Composite text layers (separate array with richer styling data)
            for textLayer in sortedTextLayers {
                let seconds = currentTime.seconds
                guard seconds >= textLayer.startSeconds && seconds < textLayer.endSeconds else { continue }
                if let textImage = renderTextImage(textLayer, canvasSize: outputSize) {
                    canvas = textImage.composited(over: canvas)
                }
            }

            // Write composited frame
            if let pool = adaptor.pixelBufferPool {
                var outputBuffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outputBuffer)
                if let buffer = outputBuffer {
                    ciContext.render(canvas, to: buffer)
                    adaptor.append(buffer, withPresentationTime: currentTime)
                }
            }

            frameCount += 1
            progressHandler(min(Double(frameCount) / totalFrames, 0.90))
            currentTime = CMTimeAdd(currentTime, frameDuration)
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw writer.error ?? CompositionError.writerSetupFailed
        }

        // Second pass: mux composited video with mixed audio from source layers
        try await mixAudio(compositeVideoURL: tempVideoURL, segment: segment, outputURL: outputURL)
        try? FileManager.default.removeItem(at: tempVideoURL)
        progressHandler(1.0)
    }

    // MARK: - Audio Mixing

    /// Combines the composited video with audio tracks from all video layers,
    /// applying per-layer volume via AVMutableAudioMix.
    private func mixAudio(
        compositeVideoURL: URL,
        segment: TimelineSegment,
        outputURL: URL
    ) async throws {
        let composition = AVMutableComposition()

        // Insert composited video track
        let compAsset = AVURLAsset(url: compositeVideoURL)
        guard let compVideoTrack = try await compAsset.loadTracks(withMediaType: .video).first else {
            throw CompositionError.invalidAsset
        }
        let compDuration = try await compAsset.load(.duration)

        let destVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        try destVideoTrack?.insertTimeRange(
            CMTimeRange(start: .zero, duration: compDuration),
            of: compVideoTrack,
            at: .zero
        )

        // Insert audio from each video layer and build mix parameters
        var audioParams: [AVMutableAudioMixInputParameters] = []
        let videoLayers = segment.layers.filter { $0.type == .video && $0.sourceURL != nil }

        for layer in videoLayers {
            guard let url = layer.sourceURL else { continue }
            let asset = AVURLAsset(url: url)
            guard let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first else { continue }

            let assetDuration = try await asset.load(.duration).seconds
            let trimStart = layer.trimStartSeconds ?? 0
            let trimEnd = layer.trimEndSeconds ?? assetDuration
            let sourceRange = CMTimeRange(
                start: CMTime(seconds: trimStart, preferredTimescale: 600),
                end: CMTime(seconds: trimEnd, preferredTimescale: 600)
            )

            guard let destAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }

            try destAudioTrack.insertTimeRange(sourceRange, of: sourceAudioTrack, at: .zero)

            let params = AVMutableAudioMixInputParameters(track: destAudioTrack)
            params.setVolume(Float(layer.volume), at: .zero)
            audioParams.append(params)
        }

        // If no audio tracks were found, just move the composited video as-is
        if audioParams.isEmpty {
            try? FileManager.default.removeItem(at: outputURL)
            try FileManager.default.moveItem(at: compositeVideoURL, to: outputURL)
            return
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioParams

        try? FileManager.default.removeItem(at: outputURL)
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw CompositionError.exportFailed("Could not create audio mix export session")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.audioMix = audioMix

        await exportSession.export()

        if let error = exportSession.error {
            throw CompositionError.exportFailed(error.localizedDescription)
        }
    }

    // MARK: - Filter Presets

    private func applyFilterPreset(_ image: CIImage, preset: FilterPreset) -> CIImage {
        switch preset {
        case .none:
            return image
        case .vivid:
            return image.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.5,
                kCIInputContrastKey: 1.1,
            ])
        case .matte:
            return image.applyingFilter("CIPhotoEffectProcess")
        case .noir:
            return image.applyingFilter("CIPhotoEffectNoir")
        case .fade:
            return image.applyingFilter("CIPhotoEffectFade")
        }
    }

    // MARK: - Background Removal

    /// Segments a person from the frame and returns the person on a transparent background.
    private func removeBackground(
        pixelBuffer: CVPixelBuffer,
        frame: CIImage,
        request: VNGeneratePersonSegmentationRequest
    ) -> CIImage {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first else { return frame }

        let maskBuffer = observation.pixelBuffer
        let maskWidth = CGFloat(CVPixelBufferGetWidth(maskBuffer))
        let scale = frame.extent.width / maskWidth
        let maskImage = CIImage(cvPixelBuffer: maskBuffer)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let clearBg = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: frame.extent)

        return frame.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": clearBg,
            "inputMaskImage": maskImage,
        ])
    }

    // MARK: - Layer Compositing

    /// Scales and positions a layer image onto the canvas at the given normalized rect.
    private func compositeLayerImage(
        _ layerImage: CIImage,
        onto canvas: CIImage,
        at position: NormalizedRect,
        canvasSize: CGSize
    ) -> CIImage {
        guard layerImage.extent.width > 0 && layerImage.extent.height > 0 else { return canvas }

        let targetX = position.x * canvasSize.width
        // Flip Y: NormalizedRect y=0 is top, CIImage y=0 is bottom
        let targetY = (1 - position.y - position.height) * canvasSize.height
        let targetW = position.width * canvasSize.width
        let targetH = position.height * canvasSize.height

        let scaleX = targetW / layerImage.extent.width
        let scaleY = targetH / layerImage.extent.height

        let transformed = layerImage
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(by: CGAffineTransform(
                translationX: targetX - layerImage.extent.origin.x * scaleX,
                y: targetY - layerImage.extent.origin.y * scaleY
            ))

        return transformed.composited(over: canvas)
    }

    // MARK: - Text Rendering

    /// Renders a TextLayer to a full-canvas CIImage with transparency.
    private func renderTextImage(_ textLayer: TextLayer, canvasSize: CGSize) -> CIImage? {
        let style = textLayer.style
        let font = UIFont(name: style.fontName, size: CGFloat(style.fontSize))
            ?? UIFont.systemFont(ofSize: CGFloat(style.fontSize), weight: .bold)
        let textColor = UIColor(
            red: CGFloat(style.textColor.red),
            green: CGFloat(style.textColor.green),
            blue: CGFloat(style.textColor.blue),
            alpha: CGFloat(style.textColor.alpha)
        )

        let pos = textLayer.layer.position
        let layerHeight = CGFloat(style.fontSize) * 2.5
        // NormalizedRect y is 0=top, 1=bottom; UIKit origin is top-left
        let drawY = CGFloat(pos.y) * canvasSize.height
        let drawW = CGFloat(pos.width) * canvasSize.width

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        let uiImage = renderer.image { _ in
            // Highlight: draw background rect behind text
            if style.contrastMode == .highlight {
                let textSize = (textLayer.text as NSString).size(withAttributes: [.font: font])
                let padding: CGFloat = 8
                let bgWidth = min(textSize.width + padding * 2, canvasSize.width)
                let bgX = (canvasSize.width - bgWidth) / 2
                let bgRect = CGRect(x: bgX, y: drawY, width: bgWidth, height: layerHeight)
                UIColor.black.withAlphaComponent(0.7).setFill()
                UIBezierPath(roundedRect: bgRect, cornerRadius: 4).fill()
            }

            var attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
            ]

            switch style.contrastMode {
            case .stroke:
                attrs[.strokeColor] = UIColor.black
                attrs[.strokeWidth] = NSNumber(value: Float(-3.0))
            case .shadow:
                let shadow = NSShadow()
                shadow.shadowColor = UIColor.black
                shadow.shadowOffset = CGSize(width: 2, height: 2)
                shadow.shadowBlurRadius = 4
                attrs[.shadow] = shadow
            case .none, .highlight:
                break
            }

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            attrs[.paragraphStyle] = paragraph

            let drawRect = CGRect(x: 0, y: drawY, width: drawW, height: layerHeight)
            (textLayer.text as NSString).draw(in: drawRect, withAttributes: attrs)
        }

        return CIImage(image: uiImage)
    }

    // MARK: - Duration Inference

    private func inferDuration(layers: [Layer], textLayers: [TextLayer]) async throws -> Double {
        var maxDuration: Double = 0
        for layer in layers {
            switch layer.type {
            case .video:
                guard let url = layer.sourceURL else { continue }
                let asset = AVURLAsset(url: url)
                let assetDuration = try await asset.load(.duration).seconds
                let trimStart = layer.trimStartSeconds ?? 0
                let trimEnd = layer.trimEndSeconds ?? assetDuration
                maxDuration = max(maxDuration, trimEnd - trimStart)
            case .photo:
                if let trimEnd = layer.trimEndSeconds {
                    maxDuration = max(maxDuration, trimEnd)
                }
            case .text:
                break
            }
        }
        for tl in textLayers {
            maxDuration = max(maxDuration, tl.endSeconds)
        }
        return maxDuration
    }

    // MARK: - Legacy Caption Burn-In

    /// Burns captions into a video and exports the result.
    /// - Parameters:
    ///   - trimStart: Seconds into the source video where the exported clip begins.
    ///   - trimEnd: Seconds into the source video where the exported clip ends (nil = full length).
    func burnCaptions(
        inputURL: URL,
        captions: [CaptionTimestamp],
        outputURL: URL,
        trimStart: Double = 0,
        trimEnd: Double? = nil
    ) async throws {
        let asset = AVAsset(url: inputURL)
        let fullDuration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)

        guard let videoTrack = videoTracks.first else {
            throw CompositionError.invalidAsset
        }

        let size = try await videoTrack.load(.naturalSize)

        let composition = AVMutableComposition()
        let videoCompositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let audioCompositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        let startTime = CMTime(seconds: max(0, trimStart), preferredTimescale: 600)
        let endTime: CMTime = trimEnd.map { CMTime(seconds: min($0, fullDuration.seconds), preferredTimescale: 600) } ?? fullDuration
        let timeRange = CMTimeRange(start: startTime, end: endTime)

        try videoCompositionTrack?.insertTimeRange(timeRange, of: videoTrack, at: .zero)

        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            try audioCompositionTrack?.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        // Caption timestamps are in source-video time; offset by trimStart so they align
        // with the exported clip which starts at t=0.
        let trimOffset = trimStart

        // Build caption layers
        let parentLayer = CALayer()
        let videoLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: size)
        videoLayer.frame = CGRect(origin: .zero, size: size)
        parentLayer.addSublayer(videoLayer)

        let screenScale = await MainActor.run { UIScreen.main.scale }

        for caption in captions {
            let style = caption.style
            let font = UIFont(name: style.fontName, size: CGFloat(style.fontSize))
                      ?? UIFont.systemFont(ofSize: CGFloat(style.fontSize), weight: .bold)
            let textColor = UIColor(
                red: CGFloat(style.textColor.red),
                green: CGFloat(style.textColor.green),
                blue: CGFloat(style.textColor.blue),
                alpha: CGFloat(style.textColor.alpha)
            )
            let layerHeight = CGFloat(style.fontSize) * 2.5
            // verticalPosition is normalized 0=top, 1=bottom; CALayer y increases upward from bottom
            let yPosition = CGFloat((1.0 - caption.verticalPosition) * Double(size.height))

            // For highlight: add background layer behind text layer
            if style.contrastMode == .highlight {
                let textSize = (caption.text as NSString).size(withAttributes: [.font: font])
                let padding: CGFloat = 8
                let bgWidth = min(textSize.width + padding * 2, size.width)
                let bgX = (size.width - bgWidth) / 2
                let bgLayer = CALayer()
                bgLayer.frame = CGRect(x: bgX, y: yPosition, width: bgWidth, height: layerHeight)
                bgLayer.backgroundColor = UIColor.black.withAlphaComponent(0.7).cgColor
                bgLayer.cornerRadius = 4
                bgLayer.opacity = 0
                addFadeAnimations(
                    to: bgLayer,
                    startTime: caption.startSeconds - trimOffset,
                    endTime: caption.endSeconds - trimOffset,
                    suffix: caption.id.uuidString + "_bg"
                )
                parentLayer.addSublayer(bgLayer)
            }

            let textLayer = CATextLayer()
            textLayer.frame = CGRect(x: 0, y: yPosition, width: size.width, height: layerHeight)
            textLayer.alignmentMode = .center
            textLayer.contentsScale = screenScale
            textLayer.isWrapped = true
            textLayer.opacity = 0

            switch style.contrastMode {
            case .none:
                textLayer.string = caption.text
                textLayer.font = font
                textLayer.fontSize = CGFloat(style.fontSize)
                textLayer.foregroundColor = textColor.cgColor

            case .stroke:
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: textColor,
                    .strokeColor: UIColor.black,
                    .strokeWidth: Float(-3.0)
                ]
                textLayer.string = NSAttributedString(string: caption.text, attributes: attrs)

            case .highlight:
                textLayer.string = caption.text
                textLayer.font = font
                textLayer.fontSize = CGFloat(style.fontSize)
                textLayer.foregroundColor = textColor.cgColor

            case .shadow:
                textLayer.string = caption.text
                textLayer.font = font
                textLayer.fontSize = CGFloat(style.fontSize)
                textLayer.foregroundColor = textColor.cgColor
                textLayer.shadowColor = UIColor.black.cgColor
                textLayer.shadowOffset = CGSize(width: 2, height: 2)
                textLayer.shadowRadius = 4
                textLayer.shadowOpacity = 1
            }

            addFadeAnimations(
                to: textLayer,
                startTime: caption.startSeconds - trimOffset,
                endTime: caption.endSeconds - trimOffset,
                suffix: caption.id.uuidString
            )
            parentLayer.addSublayer(textLayer)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = size
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        if let vct = videoCompositionTrack {
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: vct)
            instruction.layerInstructions = [layerInstruction]
        }
        videoComposition.instructions = [instruction]

        try? FileManager.default.removeItem(at: outputURL)
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw CompositionError.exportFailed("Could not create export session")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition

        await exportSession.export()

        if let error = exportSession.error {
            throw CompositionError.exportFailed(error.localizedDescription)
        }
    }

    // MARK: - Animation Helpers

    private func addFadeAnimations(to layer: CALayer, startTime: Double, endTime: Double, suffix: String) {
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.beginTime = startTime
        fadeIn.duration = 0.1
        fadeIn.isRemovedOnCompletion = false
        fadeIn.fillMode = .forwards

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1
        fadeOut.toValue = 0
        fadeOut.beginTime = endTime - 0.1
        fadeOut.duration = 0.1
        fadeOut.isRemovedOnCompletion = false
        fadeOut.fillMode = .forwards

        layer.add(fadeIn, forKey: "fadeIn_\(suffix)")
        layer.add(fadeOut, forKey: "fadeOut_\(suffix)")
    }
}
