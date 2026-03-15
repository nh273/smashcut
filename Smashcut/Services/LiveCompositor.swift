import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

// MARK: - Compositor Instruction

/// Custom instruction carrying per-layer metadata for the live compositor.
final class LiveCompositorInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    struct VideoLayerInfo {
        let trackID: CMPersistentTrackID
        let position: NormalizedRect
        let filter: FilterPreset
        let hasBackgroundRemoval: Bool
        let zIndex: Int
        let borderWidth: Double
        let cornerRadius: Double
    }

    struct PhotoLayerInfo {
        let image: CIImage
        let position: NormalizedRect
        let filter: FilterPreset
        let zIndex: Int
        let borderWidth: Double
        let cornerRadius: Double
    }

    struct TextLayerInfo {
        let textLayer: TextLayer
    }

    let videoLayers: [VideoLayerInfo]
    let photoLayers: [PhotoLayerInfo]
    let textLayers: [TextLayerInfo]
    let outputSize: CGSize

    init(
        timeRange: CMTimeRange,
        videoLayers: [VideoLayerInfo],
        photoLayers: [PhotoLayerInfo],
        textLayers: [TextLayerInfo],
        outputSize: CGSize
    ) {
        self.timeRange = timeRange
        self.videoLayers = videoLayers
        self.photoLayers = photoLayers
        self.textLayers = textLayers
        self.outputSize = outputSize

        self.requiredSourceTrackIDs = videoLayers.map { NSNumber(value: $0.trackID) as NSValue }
        super.init()
    }
}

// MARK: - Live Compositor

/// Real-time multi-layer compositor for AVPlayer preview.
/// Composites video layers with filters, background removal, and positioning.
/// Photo and text layers are composited as overlays.
final class LiveCompositor: NSObject, AVVideoCompositing {
    var sourcePixelBufferAttributes: [String: Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]

    var requiredPixelBufferAttributesForRenderContext: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let renderQueue = DispatchQueue(label: "com.smashcut.livecompositor", qos: .userInteractive)

    // Segmentation request reused across frames
    private lazy var segRequest: VNGeneratePersonSegmentationRequest = {
        let req = VNGeneratePersonSegmentationRequest()
        req.qualityLevel = .balanced
        req.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return req
    }()

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ asyncRequest: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async { [weak self] in
            self?.processRequest(asyncRequest)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {}

    // MARK: - Rendering

    private func processRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? LiveCompositorInstruction else {
            request.finish(with: NSError(domain: "LiveCompositor", code: -1))
            return
        }

        let size = instruction.outputSize
        let canvasRect = CGRect(origin: .zero, size: size)
        var canvas = CIImage(color: CIColor.black).cropped(to: canvasRect)

        // Gather all layers with z-index for sorting
        struct CompositeItem {
            let zIndex: Int
            let render: () -> CIImage?
        }

        var items: [CompositeItem] = []

        // Video layers
        for vl in instruction.videoLayers {
            items.append(CompositeItem(zIndex: vl.zIndex) { [weak self] in
                guard let self,
                      let sourceBuffer = request.sourceFrame(byTrackID: vl.trackID) else { return nil }
                var frame = CIImage(cvPixelBuffer: sourceBuffer)

                if vl.hasBackgroundRemoval {
                    frame = self.removeBackground(pixelBuffer: sourceBuffer, frame: frame)
                }
                if vl.filter != .none {
                    frame = self.applyFilter(frame, preset: vl.filter)
                }
                frame = self.positionLayer(frame, at: vl.position, canvasSize: size)
                if vl.cornerRadius > 0 || vl.borderWidth > 0 {
                    frame = self.applyBorderAndRadius(frame, borderWidth: vl.borderWidth, cornerRadius: vl.cornerRadius, position: vl.position, canvasSize: size)
                }
                return frame
            })
        }

        // Photo layers
        for pl in instruction.photoLayers {
            items.append(CompositeItem(zIndex: pl.zIndex) { [weak self] in
                guard let self else { return nil }
                var photo = pl.image
                if pl.filter != .none {
                    photo = self.applyFilter(photo, preset: pl.filter)
                }
                photo = self.positionLayer(photo, at: pl.position, canvasSize: size)
                return photo
            })
        }

        // Text layers
        let currentSeconds = request.compositionTime.seconds
        for tl in instruction.textLayers {
            let textLayer = tl.textLayer
            guard currentSeconds >= textLayer.startSeconds && currentSeconds < textLayer.endSeconds else { continue }
            items.append(CompositeItem(zIndex: textLayer.layer.zIndex) { [weak self] in
                self?.renderText(textLayer, canvasSize: size)
            })
        }

        // Sort by z-index and composite
        items.sort { $0.zIndex < $1.zIndex }
        for item in items {
            if let rendered = item.render() {
                canvas = rendered.composited(over: canvas)
            }
        }

        // Render to output buffer
        guard let outputBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "LiveCompositor", code: -2))
            return
        }

        ciContext.render(canvas, to: outputBuffer)
        request.finish(withComposedVideoFrame: outputBuffer)
    }

    // MARK: - Layer Operations

    private func positionLayer(_ image: CIImage, at position: NormalizedRect, canvasSize: CGSize) -> CIImage {
        guard image.extent.width > 0 && image.extent.height > 0 else { return image }

        let targetX = position.x * canvasSize.width
        let targetY = (1 - position.y - position.height) * canvasSize.height
        let targetW = position.width * canvasSize.width
        let targetH = position.height * canvasSize.height

        let scaleX = targetW / image.extent.width
        let scaleY = targetH / image.extent.height

        return image
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(by: CGAffineTransform(
                translationX: targetX - image.extent.origin.x * scaleX,
                y: targetY - image.extent.origin.y * scaleY
            ))
    }

    private func applyFilter(_ image: CIImage, preset: FilterPreset) -> CIImage {
        switch preset {
        case .none: return image
        case .vivid:
            return image.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.5,
                kCIInputContrastKey: 1.1,
            ])
        case .matte: return image.applyingFilter("CIPhotoEffectProcess")
        case .noir: return image.applyingFilter("CIPhotoEffectNoir")
        case .fade: return image.applyingFilter("CIPhotoEffectFade")
        }
    }

    private func removeBackground(pixelBuffer: CVPixelBuffer, frame: CIImage) -> CIImage {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        guard (try? handler.perform([segRequest])) != nil,
              let observation = segRequest.results?.first else { return frame }

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

    private func applyBorderAndRadius(
        _ image: CIImage,
        borderWidth: Double,
        cornerRadius: Double,
        position: NormalizedRect,
        canvasSize: CGSize
    ) -> CIImage {
        guard cornerRadius > 0 else { return image }

        let targetW = position.width * canvasSize.width
        let targetH = position.height * canvasSize.height
        let targetX = position.x * canvasSize.width
        let targetY = (1 - position.y - position.height) * canvasSize.height
        let rect = CGRect(x: targetX, y: targetY, width: targetW, height: targetH)

        // Render a rounded rectangle mask using UIGraphicsImageRenderer
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        let maskUIImage = renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: CGFloat(cornerRadius)).fill()
        }
        guard let maskCI = CIImage(image: maskUIImage) else { return image }

        let clearBg = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: image.extent)

        return image.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": clearBg,
            "inputMaskImage": maskCI,
        ])
    }

    private func renderText(_ textLayer: TextLayer, canvasSize: CGSize) -> CIImage? {
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
        let drawY = CGFloat(pos.y) * canvasSize.height
        let drawW = CGFloat(pos.width) * canvasSize.width

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        let uiImage = renderer.image { _ in
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
}

// MARK: - Composition Builder

/// Builds an AVMutableComposition + AVMutableVideoComposition for live preview of a segment.
enum LiveCompositionBuilder {
    struct Result {
        let composition: AVMutableComposition
        let videoComposition: AVMutableVideoComposition
        let audioMix: AVMutableAudioMix
    }

    /// Builds the playable composition for a TimelineSegment.
    /// Each video layer becomes a separate track; the custom compositor merges them.
    static func build(segment: TimelineSegment) async throws -> Result {
        let composition = AVMutableComposition()
        let allLayers = segment.layers.sorted { $0.zIndex < $1.zIndex }
        let videoLayers = allLayers.filter { $0.type == .video && $0.sourceURL != nil }

        // Determine output size from first video layer
        var outputSize = CGSize(width: 1080, height: 1920)
        if let firstVideo = videoLayers.first, let url = firstVideo.sourceURL {
            let asset = AVURLAsset(url: url)
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                outputSize = try await track.load(.naturalSize)
            }
        }

        // Calculate total duration
        var totalSeconds = segment.duration
        if totalSeconds <= 0 {
            totalSeconds = 5 // fallback
            for layer in videoLayers {
                guard let url = layer.sourceURL else { continue }
                let asset = AVURLAsset(url: url)
                let dur = try await asset.load(.duration).seconds
                let trimStart = layer.trimStartSeconds ?? 0
                let trimEnd = layer.trimEndSeconds ?? dur
                totalSeconds = max(totalSeconds, trimEnd - trimStart)
            }
        }
        let totalDuration = CMTime(seconds: totalSeconds, preferredTimescale: 600)

        // Add video tracks and build layer info
        var videoLayerInfos: [LiveCompositorInstruction.VideoLayerInfo] = []
        var audioParams: [AVMutableAudioMixInputParameters] = []

        for layer in videoLayers {
            guard let url = layer.sourceURL else { continue }
            // Use cached URL for bg-removed layers
            let effectiveURL: URL
            if layer.hasBackgroundRemoval, let cached = layer.cachedProcessedURL,
               FileManager.default.fileExists(atPath: cached.path) {
                effectiveURL = cached
            } else {
                effectiveURL = url
            }

            let asset = AVURLAsset(url: effectiveURL)
            guard let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first else { continue }
            let assetDuration = try await asset.load(.duration).seconds

            let trimStart = layer.trimStartSeconds ?? 0
            let trimEnd = layer.trimEndSeconds ?? assetDuration
            let sourceRange = CMTimeRange(
                start: CMTime(seconds: trimStart, preferredTimescale: 600),
                end: CMTime(seconds: min(trimEnd, assetDuration), preferredTimescale: 600)
            )

            guard let destTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }

            try destTrack.insertTimeRange(sourceRange, of: sourceVideoTrack, at: .zero)

            videoLayerInfos.append(LiveCompositorInstruction.VideoLayerInfo(
                trackID: destTrack.trackID,
                position: layer.position,
                filter: layer.filter,
                hasBackgroundRemoval: layer.hasBackgroundRemoval && layer.cachedProcessedURL == nil,
                zIndex: layer.zIndex,
                borderWidth: layer.borderWidth,
                cornerRadius: layer.cornerRadius
            ))

            // Audio track
            if let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first {
                if let destAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) {
                    try destAudioTrack.insertTimeRange(sourceRange, of: sourceAudioTrack, at: .zero)
                    let params = AVMutableAudioMixInputParameters(track: destAudioTrack)
                    params.setVolume(Float(layer.volume), at: .zero)
                    audioParams.append(params)
                }
            }
        }

        // Photo layers
        var photoLayerInfos: [LiveCompositorInstruction.PhotoLayerInfo] = []
        for layer in allLayers where layer.type == .photo {
            guard let url = layer.sourceURL,
                  let uiImage = UIImage(contentsOfFile: url.path),
                  let ci = CIImage(image: uiImage) else { continue }
            photoLayerInfos.append(LiveCompositorInstruction.PhotoLayerInfo(
                image: ci,
                position: layer.position,
                filter: layer.filter,
                zIndex: layer.zIndex,
                borderWidth: layer.borderWidth,
                cornerRadius: layer.cornerRadius
            ))
        }

        // Text layers
        let textLayerInfos = segment.textLayers
            .sorted { $0.layer.zIndex < $1.layer.zIndex }
            .map { LiveCompositorInstruction.TextLayerInfo(textLayer: $0) }

        // Build instruction
        let instruction = LiveCompositorInstruction(
            timeRange: CMTimeRange(start: .zero, duration: totalDuration),
            videoLayers: videoLayerInfos,
            photoLayers: photoLayerInfos,
            textLayers: textLayerInfos,
            outputSize: outputSize
        )

        // Build video composition
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = outputSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]
        videoComposition.customVideoCompositorClass = LiveCompositor.self

        // Audio mix
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioParams

        return Result(composition: composition, videoComposition: videoComposition, audioMix: audioMix)
    }
}
