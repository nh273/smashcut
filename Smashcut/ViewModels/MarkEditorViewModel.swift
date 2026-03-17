import AVFoundation
import Observation

@Observable
class MarkEditorViewModel {
    var sectionEdit: SectionEdit
    let sourceMedia: SourceMedia

    var player: AVPlayer
    var duration: Double = 0
    var currentTime: Double = 0
    var isPlaying: Bool = false

    /// The mark currently being edited (in-progress, not yet committed).
    var pendingMarkIn: Double?

    /// Currently selected mark for editing.
    var selectedMarkID: UUID?

    private var timeObserver: Any?

    init(sectionEdit: SectionEdit, sourceMedia: SourceMedia) {
        self.sectionEdit = sectionEdit
        self.sourceMedia = sourceMedia
        self.player = AVPlayer(url: sourceMedia.url)
        setupTimeObserver()
        Task { await loadDuration() }
    }

    /// Marks for this specific source media.
    var marks: [Mark] {
        sectionEdit.marks.filter { $0.sourceMediaID == sourceMedia.id }
    }

    // MARK: - Mark Actions

    /// Set the in-point at current playhead position.
    func markIn() {
        pendingMarkIn = max(0, currentTime)
    }

    /// Set the out-point and create a mark from the pending in-point.
    func markOut() {
        guard let inPoint = pendingMarkIn else { return }
        let outPoint = min(currentTime, duration > 0 ? duration : .infinity)
        guard outPoint > inPoint else { return }

        let mark = Mark(
            sourceMediaID: sourceMedia.id,
            inSeconds: inPoint,
            outSeconds: outPoint
        )
        sectionEdit.marks.append(mark)
        pendingMarkIn = nil

        // Auto-create A-roll from first mark if no rolls exist
        if sectionEdit.rolls.isEmpty {
            let rollLayer = RollLayer(
                markID: mark.id,
                layer: Layer(
                    type: .video,
                    sourceURL: sourceMedia.url,
                    zIndex: 0,
                    trimStartSeconds: mark.inSeconds,
                    trimEndSeconds: mark.outSeconds
                )
            )
            let aRoll = Roll(
                name: "A-Roll",
                startOffset: 0,
                duration: mark.duration,
                layers: [rollLayer]
            )
            sectionEdit.rolls = [aRoll]
        }

        updateStatus()
    }

    /// Delete a mark and cascade-remove from rolls.
    func deleteMark(_ mark: Mark) {
        sectionEdit.marks.removeAll { $0.id == mark.id }
        // Cascade: remove roll layers that reference this mark
        for i in sectionEdit.rolls.indices {
            sectionEdit.rolls[i].layers.removeAll { $0.markID == mark.id }
        }
        // Remove empty rolls
        sectionEdit.rolls.removeAll { $0.layers.isEmpty }
        if selectedMarkID == mark.id {
            selectedMarkID = nil
        }
        updateStatus()
    }

    /// Update a mark's in/out points.
    func updateMark(id: UUID, inSeconds: Double, outSeconds: Double) {
        guard outSeconds > inSeconds,
              inSeconds >= 0,
              let idx = sectionEdit.marks.firstIndex(where: { $0.id == id }) else { return }
        sectionEdit.marks[idx].inSeconds = inSeconds
        sectionEdit.marks[idx].outSeconds = outSeconds
    }

    /// Cancel the in-progress mark.
    func cancelPending() {
        pendingMarkIn = nil
    }

    // MARK: - Playback

    func seek(to seconds: Double) {
        let t = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    func seekToMark(_ mark: Mark) {
        seek(to: mark.inSeconds)
        selectedMarkID = mark.id
    }

    func teardown() {
        player.pause()
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
            timeObserver = nil
        }
    }

    // MARK: - Private

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
        let asset = AVAsset(url: sourceMedia.url)
        guard let dur = try? await asset.load(.duration),
              dur.isValid && !dur.isIndefinite else { return }
        await MainActor.run { self.duration = max(0, dur.seconds) }
    }

    private func updateStatus() {
        if sectionEdit.marks.isEmpty {
            if sectionEdit.mediaBin.isEmpty {
                sectionEdit.status = .empty
            } else {
                sectionEdit.status = .hasMedia
            }
        } else {
            sectionEdit.status = .marked
        }
    }
}
