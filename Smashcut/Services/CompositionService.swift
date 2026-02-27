import AVFoundation
import CoreText
import Foundation
import UIKit

actor CompositionService {
    static let shared = CompositionService()

    enum CompositionError: LocalizedError {
        case exportFailed(String)
        case invalidAsset

        var errorDescription: String? {
            switch self {
            case .exportFailed(let msg): return "Export failed: \(msg)"
            case .invalidAsset: return "Invalid video asset"
            }
        }
    }

    /// Burns captions into a video and exports the result.
    func burnCaptions(
        inputURL: URL,
        captions: [CaptionTimestamp],
        outputURL: URL
    ) async throws {
        let asset = AVAsset(url: inputURL)
        let duration = try await asset.load(.duration)
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

        let timeRange = CMTimeRange(start: .zero, duration: duration)
        try videoCompositionTrack?.insertTimeRange(timeRange, of: videoTrack, at: .zero)

        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            try audioCompositionTrack?.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        // Build caption layers
        let parentLayer = CALayer()
        let videoLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: size)
        videoLayer.frame = CGRect(origin: .zero, size: size)
        parentLayer.addSublayer(videoLayer)

        for caption in captions {
            let textLayer = CATextLayer()
            textLayer.string = caption.text
            textLayer.font = UIFont.boldSystemFont(ofSize: 44)
            textLayer.fontSize = 44
            textLayer.foregroundColor = UIColor.white.cgColor
            textLayer.shadowColor = UIColor.black.cgColor
            textLayer.shadowOffset = CGSize(width: 2, height: 2)
            textLayer.shadowRadius = 4
            textLayer.alignmentMode = .center
            textLayer.contentsScale = UIScreen.main.scale
            textLayer.frame = CGRect(x: 0, y: 80, width: size.width, height: 100)
            textLayer.opacity = 0

            let startTime = caption.startSeconds
            let endTime = caption.endSeconds

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

            textLayer.add(fadeIn, forKey: "fadeIn_\(caption.id)")
            textLayer.add(fadeOut, forKey: "fadeOut_\(caption.id)")

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
        instruction.timeRange = timeRange
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
}
