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
