import AVFoundation
import Cabbage
import Foundation

// MARK: - Cabbage Compositor Spike

/// Spike: evaluates Cabbage as a composition backend by building a two-clip
/// timeline with a cross-dissolve transition and exporting via Cabbage's
/// AVMutableComposition pipeline (vs our frame-by-frame CompositionService).
enum CabbageCompositor {

    struct BenchmarkResult {
        let cabbageDuration: TimeInterval
        let legacyDuration: TimeInterval
        let outputURL: URL
        let renderSize: CGSize
    }

    // MARK: - Two-Clip Timeline with Transition

    /// Builds a Cabbage Timeline from two video URLs with a cross-dissolve
    /// transition of the given duration, then exports to `outputURL`.
    static func compose(
        clipA: URL,
        clipB: URL,
        transitionDuration: Double = 1.0,
        renderSize: CGSize = CGSize(width: 1080, height: 1920),
        outputURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()

        // Build Cabbage resources
        let assetA = AVAsset(url: clipA)
        let assetB = AVAsset(url: clipB)

        let resourceA = AVAssetTrackResource(asset: assetA)
        let resourceB = AVAssetTrackResource(asset: assetB)

        let itemA = TrackItem(resource: resourceA)
        let itemB = TrackItem(resource: resourceB)

        // Configure cross-dissolve transition on clip B
        let transition = CrossDissolveTransition(duration: CMTime(seconds: transitionDuration, preferredTimescale: 600))
        itemB.videoTransition = transition
        itemB.audioTransition = transition

        // Build timeline
        let timeline = Cabbage.Timeline()
        timeline.videoChannel = [itemA, itemB]
        timeline.audioChannel = [itemA, itemB]
        timeline.renderSize = renderSize

        // Generate composition
        let generator = CompositionGenerator(timeline: timeline)
        generator.renderSize = renderSize

        // Export
        guard let exportSession = generator.buildExportSession(presetName: AVAssetExportPresetHighestQuality) else {
            throw CabbageError.exportSessionFailed
        }

        try? FileManager.default.removeItem(at: outputURL)
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        // Poll progress
        let progressTask = Task {
            while !Task.isCancelled {
                progressHandler(Double(exportSession.progress))
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        await exportSession.export()
        progressTask.cancel()

        if let error = exportSession.error {
            throw CabbageError.exportFailed(error.localizedDescription)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        progressHandler(1.0)
        return elapsed
    }

    // MARK: - Live Preview via Cabbage

    /// Builds an AVPlayerItem for real-time preview of a two-clip timeline.
    static func buildPlayerItem(
        clipA: URL,
        clipB: URL,
        transitionDuration: Double = 1.0,
        renderSize: CGSize = CGSize(width: 1080, height: 1920)
    ) -> AVPlayerItem {
        let assetA = AVAsset(url: clipA)
        let assetB = AVAsset(url: clipB)

        let resourceA = AVAssetTrackResource(asset: assetA)
        let resourceB = AVAssetTrackResource(asset: assetB)

        let itemA = TrackItem(resource: resourceA)
        let itemB = TrackItem(resource: resourceB)

        let transition = CrossDissolveTransition(duration: CMTime(seconds: transitionDuration, preferredTimescale: 600))
        itemB.videoTransition = transition
        itemB.audioTransition = transition

        let timeline = Cabbage.Timeline()
        timeline.videoChannel = [itemA, itemB]
        timeline.audioChannel = [itemA, itemB]
        timeline.renderSize = renderSize

        let generator = CompositionGenerator(timeline: timeline)
        generator.renderSize = renderSize

        return generator.buildPlayerItem()
    }

    // MARK: - Segment Conversion

    /// Converts a Smashcut TimelineSegment into a Cabbage Timeline.
    /// Maps our Layer model to Cabbage's TrackItem + Resource model.
    static func timelineFromSegment(_ segment: TimelineSegment, renderSize: CGSize) -> Cabbage.Timeline {
        let timeline = Cabbage.Timeline()
        timeline.renderSize = renderSize

        let videoLayers = segment.layers
            .filter { $0.type == .video && $0.sourceURL != nil }
            .sorted { $0.zIndex < $1.zIndex }

        var videoItems: [TrackItem] = []
        var audioItems: [TrackItem] = []

        for layer in videoLayers {
            guard let url = layer.sourceURL else { continue }
            let asset = AVAsset(url: url)
            let resource = AVAssetTrackResource(asset: asset)

            // Apply trim
            if let trimStart = layer.trimStartSeconds {
                resource.selectedTimeRange = CMTimeRange(
                    start: CMTime(seconds: trimStart, preferredTimescale: 600),
                    duration: CMTime(
                        seconds: (layer.trimEndSeconds ?? 0) - trimStart,
                        preferredTimescale: 600
                    )
                )
            }

            let item = TrackItem(resource: resource)

            // Map filter preset to Cabbage video configuration
            if layer.filter != .none {
                item.videoConfiguration.configurations.append(
                    FilterConfiguration(preset: layer.filter)
                )
            }

            videoItems.append(item)
            audioItems.append(item)
        }

        timeline.videoChannel = videoItems
        timeline.audioChannel = audioItems

        return timeline
    }

    // MARK: - Benchmark

    /// Runs both Cabbage and legacy CompositionService on the same two-clip
    /// input, returning timing for comparison.
    static func benchmark(
        clipA: URL,
        clipB: URL,
        renderSize: CGSize = CGSize(width: 1080, height: 1920)
    ) async throws -> BenchmarkResult {
        let tempDir = FileManager.default.temporaryDirectory
        let cabbageOut = tempDir.appendingPathComponent("cabbage_bench_\(UUID().uuidString).mp4")
        let legacyOut = tempDir.appendingPathComponent("legacy_bench_\(UUID().uuidString).mp4")

        // Cabbage export
        let cabbageTime = try await compose(
            clipA: clipA, clipB: clipB,
            renderSize: renderSize,
            outputURL: cabbageOut,
            progressHandler: { _ in }
        )

        // Legacy frame-by-frame export
        let legacyStart = CFAbsoluteTimeGetCurrent()
        let segment = TimelineSegment(scriptText: "benchmark")
        var seg = segment
        seg.layers = [
            Layer(type: .video, sourceURL: clipA, zIndex: 0),
            Layer(type: .video, sourceURL: clipB, zIndex: 1),
        ]
        try await CompositionService.shared.compose(
            segment: seg, outputURL: legacyOut, progressHandler: { _ in }
        )
        let legacyTime = CFAbsoluteTimeGetCurrent() - legacyStart

        // Clean up legacy output
        try? FileManager.default.removeItem(at: legacyOut)

        return BenchmarkResult(
            cabbageDuration: cabbageTime,
            legacyDuration: legacyTime,
            outputURL: cabbageOut,
            renderSize: renderSize
        )
    }
}

// MARK: - Cross-Dissolve Transition

/// Simple cross-dissolve implemented via Cabbage's VideoTransition protocol.
private class CrossDissolveTransition: NSObject, VideoTransition, AudioTransition {
    var identifier: String { "com.smashcut.crossDissolve" }
    let duration: CMTime

    init(duration: CMTime) {
        self.duration = duration
        super.init()
    }

    func renderImage(
        foregroundImage: CIImage,
        backgroundImage: CIImage,
        forTweenFactor tween: Float64,
        renderSize: CGSize
    ) -> CIImage {
        foregroundImage.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: backgroundImage,
            "inputTime": NSNumber(value: tween),
        ])
    }

    func applyPreviousAudioMixInputParameters(
        _ parameters: AVMutableAudioMixInputParameters,
        timeRange: CMTimeRange
    ) {
        parameters.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: timeRange)
    }

    func applyNextAudioMixInputParameters(
        _ parameters: AVMutableAudioMixInputParameters,
        timeRange: CMTimeRange
    ) {
        parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: timeRange)
    }
}

// MARK: - Filter Bridge

/// Bridges our FilterPreset to Cabbage's VideoConfigurationProtocol.
private class FilterConfiguration: NSObject, VideoConfigurationProtocol {
    let preset: FilterPreset

    init(preset: FilterPreset) {
        self.preset = preset
        super.init()
    }

    func copy(with zone: NSZone? = nil) -> Any {
        FilterConfiguration(preset: preset)
    }

    func applyEffect(to sourceImage: CIImage, info: VideoConfigurationEffectInfo) -> CIImage {
        switch preset {
        case .none:
            return sourceImage
        case .vivid:
            return sourceImage.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.5,
                kCIInputContrastKey: 1.1,
            ])
        case .matte:
            return sourceImage.applyingFilter("CIPhotoEffectProcess")
        case .noir:
            return sourceImage.applyingFilter("CIPhotoEffectNoir")
        case .fade:
            return sourceImage.applyingFilter("CIPhotoEffectFade")
        }
    }
}

// MARK: - Errors

enum CabbageError: LocalizedError {
    case exportSessionFailed
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .exportSessionFailed:
            return "Failed to create Cabbage export session"
        case .exportFailed(let msg):
            return "Cabbage export failed: \(msg)"
        }
    }
}
