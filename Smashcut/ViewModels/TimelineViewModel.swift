import AVFoundation
import Observation

@Observable
class TimelineViewModel {
    var project: Project
    var timeline: ProjectTimeline

    // Playback
    let player: AVPlayer = AVPlayer()
    var isPlaying = false
    var currentTime: Double = 0
    var currentSegmentIndex: Int = 0

    // UI
    var scale: CGFloat = 80 // points per second
    var selectedSegmentID: UUID?

    /// When true, user is actively scrubbing — suppress auto-scroll from playback.
    var isScrubbing = false

    private var timeObserver: Any?

    var totalDuration: Double {
        timeline.segments.reduce(0) { $0 + $1.duration }
    }

    init(project: Project) {
        self.project = project
        self.timeline = project.timeline ?? ProjectTimeline()
        setupTimeObserver()
        if let first = timeline.segments.first {
            selectedSegmentID = first.id
            loadSegmentPlayer(at: 0)
        }
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

    func selectSegment(at index: Int) {
        guard index >= 0, index < timeline.segments.count else { return }
        currentSegmentIndex = index
        selectedSegmentID = timeline.segments[index].id
        let globalTime = segmentStartTime(at: index)
        currentTime = globalTime
        loadSegmentPlayer(at: index)
        let cmTime = CMTime(seconds: 0, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func seek(to globalTime: Double) {
        let clamped = max(0, min(globalTime, totalDuration))
        currentTime = clamped
        let segIdx = segmentIndex(at: clamped)
        if segIdx != currentSegmentIndex {
            currentSegmentIndex = segIdx
            selectedSegmentID = timeline.segments[segIdx].id
            loadSegmentPlayer(at: segIdx)
        }
        let localTime = clamped - segmentStartTime(at: segIdx)
        let cmTime = CMTime(seconds: localTime, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    // MARK: - Editing

    func updateSegmentDuration(segmentID: UUID, duration: Double) {
        guard let idx = timeline.segments.firstIndex(where: { $0.id == segmentID }) else { return }
        timeline.segments[idx].duration = max(0.5, duration)
    }

    func updateLayerOffset(segmentID: UUID, layerID: UUID, offset: Double) {
        guard let segIdx = timeline.segments.firstIndex(where: { $0.id == segmentID }),
              let layIdx = timeline.segments[segIdx].layers.firstIndex(where: { $0.id == layerID })
        else { return }
        timeline.segments[segIdx].layers[layIdx].startOffset = max(0, offset)
    }

    func updateLayerVolume(segmentID: UUID, layerID: UUID, volume: Double) {
        guard let segIdx = timeline.segments.firstIndex(where: { $0.id == segmentID }),
              let layIdx = timeline.segments[segIdx].layers.firstIndex(where: { $0.id == layerID })
        else { return }
        timeline.segments[segIdx].layers[layIdx].volume = max(0, min(1, volume))
    }

    func moveSegment(from source: IndexSet, to destination: Int) {
        timeline.segments.move(fromOffsets: source, toOffset: destination)
    }

    /// Split the selected segment into two at the current playhead position.
    /// Returns true if split succeeded.
    @discardableResult
    func splitAtPlayhead() -> Bool {
        guard let segID = selectedSegmentID,
              let segIdx = timeline.segments.firstIndex(where: { $0.id == segID })
        else { return false }

        let segment = timeline.segments[segIdx]
        let segStart = segmentStartTime(at: segIdx)
        let localTime = currentTime - segStart

        // Need at least 0.1s on each side
        guard localTime >= 0.1, localTime <= segment.duration - 0.1 else { return false }

        let (left, right) = TimelineSegment.split(segment, at: localTime)

        timeline.segments.replaceSubrange(segIdx...segIdx, with: [left, right])
        selectedSegmentID = left.id
        currentSegmentIndex = segIdx
        loadSegmentPlayer(at: segIdx)
        let cmTime = CMTime(seconds: localTime, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        return true
    }

    func saveChanges(to appState: AppState) {
        var updated = project
        updated.timeline = timeline
        appState.updateProject(updated)
    }

    func teardown() {
        player.pause()
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
            timeObserver = nil
        }
    }

    // MARK: - Private

    private func loadSegmentPlayer(at index: Int) {
        guard index >= 0, index < timeline.segments.count else { return }
        let segment = timeline.segments[index]
        guard let videoLayer = segment.layers.first(where: { $0.type == .video && $0.sourceURL != nil }),
              let url = videoLayer.sourceURL else {
            player.replaceCurrentItem(with: nil)
            return
        }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
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
                    self.selectedSegmentID = self.timeline.segments[nextIdx].id
                    self.loadSegmentPlayer(at: nextIdx)
                    self.player.play()
                } else {
                    self.player.pause()
                    self.isPlaying = false
                }
            }
        }
    }
}
