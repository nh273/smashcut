import AVFoundation
import Observation
import UIKit

/// ViewModel for the full project draft preview.
/// Stitches all TimelineSegments into continuous playback using per-segment
/// LiveCompositionBuilder compositions. Auto-advances between segments.
@Observable
class DraftPreviewViewModel {
    var project: Project
    var timeline: ProjectTimeline

    // Playback
    let player = AVPlayer()
    var isPlaying = false
    var currentTime: Double = 0
    var currentSegmentIndex: Int = 0

    // Segment thumbnails
    var segmentThumbnails: [UUID: UIImage] = [:]

    // Edit flow
    var editingSegmentIndex: Int?

    private var timeObserver: Any?
    private var buildTask: Task<Void, Never>?

    var totalDuration: Double {
        timeline.segments.reduce(0) { $0 + $1.duration }
    }

    /// Cumulative start times for each segment.
    var segmentStartTimes: [Double] {
        var times: [Double] = []
        var acc: Double = 0
        for segment in timeline.segments {
            times.append(acc)
            acc += segment.duration
        }
        return times
    }

    init(project: Project) {
        self.project = project
        self.timeline = project.timeline ?? ProjectTimeline()
        setupTimeObserver()
        if !timeline.segments.isEmpty {
            loadSegment(at: 0)
        }
        generateThumbnails()
    }

    // MARK: - Time Mapping

    func segmentStartTime(at index: Int) -> Double {
        guard index > 0, index <= timeline.segments.count else { return 0 }
        return timeline.segments[..<index].reduce(0) { $0 + $1.duration }
    }

    func segmentIndex(at globalTime: Double) -> Int {
        var accumulated: Double = 0
        for (i, segment) in timeline.segments.enumerated() {
            accumulated += segment.duration
            if globalTime < accumulated { return i }
        }
        return max(0, timeline.segments.count - 1)
    }

    // MARK: - Playback

    func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func seek(to globalTime: Double) {
        let clamped = max(0, min(globalTime, totalDuration))
        currentTime = clamped
        let segIdx = segmentIndex(at: clamped)
        if segIdx != currentSegmentIndex {
            currentSegmentIndex = segIdx
            loadSegment(at: segIdx)
        }
        let localTime = clamped - segmentStartTime(at: segIdx)
        let cmTime = CMTime(seconds: localTime, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func skipForward() {
        seek(to: currentTime + 15)
    }

    func skipBackward() {
        seek(to: currentTime - 15)
    }

    func jumpToSegment(at index: Int) {
        guard index >= 0, index < timeline.segments.count else { return }
        let wasPlaying = isPlaying
        currentSegmentIndex = index
        currentTime = segmentStartTime(at: index)
        loadSegment(at: index)
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        if wasPlaying {
            player.play()
        }
    }

    // MARK: - Edit Flow

    func editCurrentSegment() {
        player.pause()
        isPlaying = false
        editingSegmentIndex = currentSegmentIndex
    }

    func refreshAfterEdit(from appState: AppState) {
        guard let updated = appState.projects.first(where: { $0.id == project.id }) else { return }
        project = updated
        timeline = updated.timeline ?? ProjectTimeline()
        let savedTime = currentTime
        loadSegment(at: currentSegmentIndex)
        // Seek back to where we were
        let localTime = savedTime - segmentStartTime(at: currentSegmentIndex)
        let cmTime = CMTime(seconds: max(0, localTime), preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        generateThumbnails()
    }

    func teardown() {
        player.pause()
        buildTask?.cancel()
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
            timeObserver = nil
        }
    }

    // MARK: - Private

    private func loadSegment(at index: Int) {
        guard index >= 0, index < timeline.segments.count else { return }
        let segment = timeline.segments[index]

        buildTask?.cancel()
        buildTask = Task { @MainActor in
            do {
                let result = try await LiveCompositionBuilder.build(segment: segment)
                let item = AVPlayerItem(asset: result.composition)
                item.videoComposition = result.videoComposition
                item.audioMix = result.audioMix
                player.replaceCurrentItem(with: item)
            } catch {
                // Fallback: load first video layer directly
                if let firstVideo = segment.layers.first(where: { $0.type == .video }),
                   let url = firstVideo.sourceURL {
                    player.replaceCurrentItem(with: AVPlayerItem(url: url))
                } else {
                    player.replaceCurrentItem(with: nil)
                }
            }
        }
    }

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.033, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, self.isPlaying else { return }
            let localTime = max(0, time.seconds)
            let segStart = self.segmentStartTime(at: self.currentSegmentIndex)
            let segDuration = self.currentSegmentIndex < self.timeline.segments.count
                ? self.timeline.segments[self.currentSegmentIndex].duration : 0
            self.currentTime = segStart + localTime

            // Auto-advance to next segment
            if localTime >= segDuration {
                let nextIdx = self.currentSegmentIndex + 1
                if nextIdx < self.timeline.segments.count {
                    self.currentSegmentIndex = nextIdx
                    self.loadSegment(at: nextIdx)
                    self.player.play()
                } else {
                    self.player.pause()
                    self.isPlaying = false
                }
            }
        }
    }

    private func generateThumbnails() {
        for segment in timeline.segments {
            guard let videoLayer = segment.layers.first(where: { $0.type == .video }),
                  let url = videoLayer.sourceURL else { continue }
            let segmentID = segment.id
            Task {
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 120, height: 120)
                if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                    let thumbnail = UIImage(cgImage: cgImage)
                    await MainActor.run {
                        self.segmentThumbnails[segmentID] = thumbnail
                    }
                }
            }
        }
    }
}
