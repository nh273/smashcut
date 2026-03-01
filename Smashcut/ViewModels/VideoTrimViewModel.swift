import AVFoundation
import Observation

@Observable
class VideoTrimViewModel {
    let recording: Recording

    var player: AVPlayer
    var duration: Double = 0
    var currentTime: Double = 0
    var trimStart: Double?
    var trimEnd: Double?
    var isPlaying: Bool = false

    private var timeObserver: Any?

    init(recording: Recording) {
        self.recording = recording
        self.player = AVPlayer(url: recording.rawVideoURL)
        self.trimStart = recording.trimStartSeconds
        self.trimEnd = recording.trimEndSeconds
        setupTimeObserver()
        Task { await loadDuration() }
    }

    func markEntrance() {
        trimStart = currentTime
        if let end = trimEnd, currentTime >= end {
            trimEnd = nil
        }
    }

    func markExit() {
        trimEnd = currentTime
        if let start = trimStart, currentTime <= start {
            trimStart = nil
        }
    }

    func clearTrim() {
        trimStart = nil
        trimEnd = nil
    }

    func seek(to seconds: Double) {
        let t = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
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

    func teardown() {
        player.pause()
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
            timeObserver = nil
        }
    }

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.033, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let t = max(0, time.seconds)
            self.currentTime = t
            if self.duration > 0 && t >= self.duration {
                self.player.pause()
                self.isPlaying = false
            }
        }
    }

    private func loadDuration() async {
        let asset = AVAsset(url: recording.rawVideoURL)
        guard let dur = try? await asset.load(.duration),
              dur.isValid && !dur.isIndefinite else { return }
        await MainActor.run { self.duration = max(0, dur.seconds) }
    }
}
