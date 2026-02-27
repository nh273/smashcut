import AVFoundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Foundation

actor SegmentationService {
    static let shared = SegmentationService()

    enum SegmentationError: LocalizedError {
        case invalidAsset
        case readerSetupFailed
        case writerSetupFailed

        var errorDescription: String? {
            switch self {
            case .invalidAsset: return "Invalid video asset"
            case .readerSetupFailed: return "Failed to set up video reader"
            case .writerSetupFailed: return "Failed to set up video writer"
            }
        }
    }

    func processVideo(
        inputURL: URL,
        backgroundURL: URL?,
        backgroundIsVideo: Bool,
        outputURL: URL,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        let asset = AVAsset(url: inputURL)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard let videoTrack = videoTracks.first else {
            throw SegmentationError.invalidAsset
        }

        let size = try await videoTrack.load(.naturalSize)
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let totalSeconds = CMTimeGetSeconds(duration)
        let totalFrames = max(1.0, Double(totalSeconds) * Double(frameRate))

        // Set up reader
        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.alwaysCopiesSampleData = false
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderTrackOutput?
        if let audioTrack = audioTracks.first {
            let ao = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            ao.alwaysCopiesSampleData = false
            reader.add(ao)
            audioOutput = ao
        }

        // Set up writer
        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let writerVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerVideoInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerVideoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )
        writer.add(writerVideoInput)

        var writerAudioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            ai.expectsMediaDataInRealTime = false
            writer.add(ai)
            writerAudioInput = ai
        }

        guard reader.startReading() else {
            throw SegmentationError.readerSetupFailed
        }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Load background image (if any)
        let bgCIImage: CIImage? = loadBackgroundImage(url: backgroundIsVideo ? nil : backgroundURL, size: size)
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        var frameCount = 0

        // Process video frames
        while let sampleBuffer = videoOutput.copyNextSampleBuffer() {
            while !writerVideoInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }

            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            if let processed = processFrame(
                sampleBuffer: sampleBuffer,
                background: bgCIImage,
                request: request,
                ciContext: ciContext,
                size: size
            ) {
                adaptor.append(processed, withPresentationTime: pts)
            } else if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                adaptor.append(imageBuffer, withPresentationTime: pts)
            }

            frameCount += 1
            let progress = Double(frameCount) / totalFrames
            progressHandler(min(progress, 0.95))
        }

        // Copy audio
        if let audioOutput, let writerAudioInput {
            while let audioSample = audioOutput.copyNextSampleBuffer() {
                while !writerAudioInput.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 1_000_000)
                }
                writerAudioInput.append(audioSample)
            }
            writerAudioInput.markAsFinished()
        }

        writerVideoInput.markAsFinished()
        await writer.finishWriting()
        progressHandler(1.0)

        if writer.status == .failed {
            throw writer.error ?? SegmentationError.writerSetupFailed
        }
    }

    private func processFrame(
        sampleBuffer: CMSampleBuffer,
        background: CIImage?,
        request: VNGeneratePersonSegmentationRequest,
        ciContext: CIContext,
        size: CGSize
    ) -> CVPixelBuffer? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        let handler = VNImageRequestHandler(cvPixelBuffer: imageBuffer, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first else { return nil }
        let maskBuffer = observation.pixelBuffer

        let personImage = CIImage(cvPixelBuffer: imageBuffer)
        let maskWidth = CGFloat(CVPixelBufferGetWidth(maskBuffer))
        let scale = size.width / maskWidth
        let maskImage = CIImage(cvPixelBuffer: maskBuffer)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let bgImage = (background ?? CIImage(color: CIColor.black))
            .cropped(to: personImage.extent)

        // CIBlendWithMask: where mask is white → inputImage, where black → backgroundImage
        let composited = personImage.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": bgImage,
            "inputMaskImage": maskImage
        ])

        var outputBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height),
                            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &outputBuffer)
        guard let buffer = outputBuffer else { return nil }
        ciContext.render(composited, to: buffer)
        return buffer
    }

    private func loadBackgroundImage(url: URL?, size: CGSize) -> CIImage? {
        guard let url,
              let uiImage = UIImage(contentsOfFile: url.path),
              let ci = CIImage(image: uiImage) else { return nil }
        let scaleX = size.width / ci.extent.width
        let scaleY = size.height / ci.extent.height
        return ci.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
    }
}
