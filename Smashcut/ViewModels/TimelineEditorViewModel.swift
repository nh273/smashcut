import AVFoundation
import Observation

/// Inspector mode for the timeline editor's context-sensitive panel.
enum InspectorMode: Equatable {
    case none
    case roll(UUID)
    case layer(rollID: UUID, layerID: UUID)
    case caption(Int)
}

/// Central ViewModel for the unified TimelineEditorView, combining roll management,
/// caption editing, spatial layer editing, and playback.
@Observable
class TimelineEditorViewModel {
    var sectionEdit: SectionEdit
    let projectID: UUID

    // Playback
    let player = AVPlayer()
    var isPlaying = false
    var currentTime: Double = 0
    var duration: Double = 0

    // Selection / Inspector
    var inspectorMode: InspectorMode = .none
    var showGrid = false

    // Caption editing
    var chunks: [EditableCaptionChunk] = []
    var captionStyle: CaptionStyle
    var isLinkedMode: Bool = true

    private var timeObserver: Any?
    private var buildTask: Task<Void, Never>?

    init(sectionEdit: SectionEdit, projectID: UUID) {
        self.sectionEdit = sectionEdit
        self.projectID = projectID
        self.duration = sectionEdit.duration
        self.captionStyle = sectionEdit.captionTimestamps.first?.style ?? CaptionStyle()
        self.chunks = CaptionEditorViewModel.buildChunks(from: sectionEdit.captionTimestamps)
        setupTimeObserver()
        rebuildComposition()
    }

    // MARK: - Playback

    func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, duration))
        currentTime = clamped
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func teardown() {
        player.pause()
        buildTask?.cancel()
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
            timeObserver = nil
        }
    }

    // MARK: - Roll Management (from RollArrangerViewModel)

    var rolls: [Roll] {
        sectionEdit.rolls
    }

    var unusedMarks: [Mark] {
        let usedMarkIDs = Set(sectionEdit.rolls.flatMap { $0.layers.compactMap { $0.markID } })
        return sectionEdit.marks.filter { !usedMarkIDs.contains($0.id) }
    }

    func addRoll(name: String = "B-Roll") {
        let offset = sectionEdit.rolls.map { $0.startOffset + $0.duration }.max() ?? 0
        let roll = Roll(name: name, startOffset: offset)
        sectionEdit.rolls.append(roll)
        inspectorMode = .roll(roll.id)
        rebuildComposition()
    }

    func deleteRoll(_ rollID: UUID) {
        sectionEdit.rolls.removeAll { $0.id == rollID }
        if case .roll(rollID) = inspectorMode {
            inspectorMode = .none
        }
        updateStatus()
        rebuildComposition()
    }

    func renameRoll(id: UUID, name: String) {
        guard let idx = sectionEdit.rolls.firstIndex(where: { $0.id == id }) else { return }
        sectionEdit.rolls[idx].name = name
    }

    func updateRollTiming(id: UUID, startOffset: Double, duration: Double) {
        guard let idx = sectionEdit.rolls.firstIndex(where: { $0.id == id }) else { return }
        sectionEdit.rolls[idx].startOffset = max(0, startOffset)
        sectionEdit.rolls[idx].duration = max(0.1, duration)
        rebuildComposition()
    }

    func addMarkToRoll(markID: UUID, rollID: UUID) {
        guard let mark = sectionEdit.marks.first(where: { $0.id == markID }),
              let rollIdx = sectionEdit.rolls.firstIndex(where: { $0.id == rollID }),
              let sourceMedia = sectionEdit.mediaBin.first(where: { $0.id == mark.sourceMediaID }) else { return }

        let rollLayer = RollLayer(
            markID: markID,
            layer: Layer(
                type: sourceMedia.type,
                sourceURL: sourceMedia.url,
                zIndex: sectionEdit.rolls[rollIdx].layers.count,
                trimStartSeconds: mark.inSeconds,
                trimEndSeconds: mark.outSeconds
            )
        )
        sectionEdit.rolls[rollIdx].layers.append(rollLayer)

        if sectionEdit.rolls[rollIdx].duration <= 0 {
            sectionEdit.rolls[rollIdx].duration = mark.duration
        }

        updateStatus()
        rebuildComposition()
    }

    func removeLayerFromRoll(rollID: UUID, layerID: UUID) {
        guard let rollIdx = sectionEdit.rolls.firstIndex(where: { $0.id == rollID }) else { return }
        sectionEdit.rolls[rollIdx].layers.removeAll { $0.id == layerID }
        if rollIdx < sectionEdit.rolls.count,
           sectionEdit.rolls[rollIdx].layers.isEmpty,
           sectionEdit.rolls[rollIdx].name != "A-Roll" {
            sectionEdit.rolls.remove(at: rollIdx)
        }
        if case .layer(rollID, layerID) = inspectorMode {
            inspectorMode = .none
        }
        updateStatus()
        rebuildComposition()
    }

    // MARK: - Spatial Layer Editing (from SegmentEditViewModel)

    func updateLayerPosition(rollID: UUID, layerID: UUID, position: NormalizedRect) {
        guard let rollIdx = sectionEdit.rolls.firstIndex(where: { $0.id == rollID }),
              let layerIdx = sectionEdit.rolls[rollIdx].layers.firstIndex(where: { $0.id == layerID }) else { return }
        sectionEdit.rolls[rollIdx].layers[layerIdx].layer.position = snapToGrid(position)
        rebuildComposition()
    }

    func setLayerFilter(rollID: UUID, layerID: UUID, filter: FilterPreset) {
        guard let rollIdx = sectionEdit.rolls.firstIndex(where: { $0.id == rollID }),
              let layerIdx = sectionEdit.rolls[rollIdx].layers.firstIndex(where: { $0.id == layerID }) else { return }
        sectionEdit.rolls[rollIdx].layers[layerIdx].layer.filter = filter
        rebuildComposition()
    }

    func setLayerVolume(rollID: UUID, layerID: UUID, volume: Double) {
        guard let rollIdx = sectionEdit.rolls.firstIndex(where: { $0.id == rollID }),
              let layerIdx = sectionEdit.rolls[rollIdx].layers.firstIndex(where: { $0.id == layerID }) else { return }
        sectionEdit.rolls[rollIdx].layers[layerIdx].layer.volume = max(0, min(1, volume))
        rebuildComposition()
    }

    func setLayerBorderWidth(rollID: UUID, layerID: UUID, width: Double) {
        guard let rollIdx = sectionEdit.rolls.firstIndex(where: { $0.id == rollID }),
              let layerIdx = sectionEdit.rolls[rollIdx].layers.firstIndex(where: { $0.id == layerID }) else { return }
        sectionEdit.rolls[rollIdx].layers[layerIdx].layer.borderWidth = max(0, width)
        rebuildComposition()
    }

    func setLayerCornerRadius(rollID: UUID, layerID: UUID, radius: Double) {
        guard let rollIdx = sectionEdit.rolls.firstIndex(where: { $0.id == rollID }),
              let layerIdx = sectionEdit.rolls[rollIdx].layers.firstIndex(where: { $0.id == layerID }) else { return }
        sectionEdit.rolls[rollIdx].layers[layerIdx].layer.cornerRadius = max(0, radius)
        rebuildComposition()
    }

    func toggleBackgroundRemoval(rollID: UUID, layerID: UUID) {
        guard let rollIdx = sectionEdit.rolls.firstIndex(where: { $0.id == rollID }),
              let layerIdx = sectionEdit.rolls[rollIdx].layers.firstIndex(where: { $0.id == layerID }) else { return }
        sectionEdit.rolls[rollIdx].layers[layerIdx].layer.hasBackgroundRemoval.toggle()
        rebuildComposition()
    }

    func setLayerTrim(rollID: UUID, layerID: UUID, start: Double?, end: Double?) {
        guard let rollIdx = sectionEdit.rolls.firstIndex(where: { $0.id == rollID }),
              let layerIdx = sectionEdit.rolls[rollIdx].layers.firstIndex(where: { $0.id == layerID }) else { return }
        sectionEdit.rolls[rollIdx].layers[layerIdx].layer.trimStartSeconds = start
        sectionEdit.rolls[rollIdx].layers[layerIdx].layer.trimEndSeconds = end
        rebuildComposition()
    }

    // MARK: - Caption Editing (from CaptionEditorViewModel)

    func adjustCaptionStart(at index: Int, to newStart: Double) {
        var start = max(0, newStart)
        if isLinkedMode, index > 0 {
            start = max(start, chunks[index - 1].startSeconds + 0.1)
            start = min(start, chunks[index].endSeconds - 0.1)
            chunks[index].startSeconds = start
            chunks[index - 1].endSeconds = start
        } else {
            if index > 0 {
                start = max(start, chunks[index - 1].endSeconds + 0.05)
            }
            start = min(start, chunks[index].endSeconds - 0.1)
            chunks[index].startSeconds = start
        }
        syncCaptionsToSectionEdit()
    }

    func adjustCaptionEnd(at index: Int, to newEnd: Double) {
        var end = min(duration, newEnd)
        if isLinkedMode, index < chunks.count - 1 {
            end = min(end, chunks[index + 1].endSeconds - 0.1)
            end = max(end, chunks[index].startSeconds + 0.1)
            chunks[index].endSeconds = end
            chunks[index + 1].startSeconds = end
        } else {
            if index < chunks.count - 1 {
                end = min(end, chunks[index + 1].startSeconds - 0.05)
            }
            end = max(end, chunks[index].startSeconds + 0.1)
            chunks[index].endSeconds = end
        }
        syncCaptionsToSectionEdit()
    }

    func setCaptionText(at index: Int, text: String) {
        guard index < chunks.count else { return }
        chunks[index].text = text
        syncCaptionsToSectionEdit()
    }

    func setCaptionVerticalPosition(at index: Int, position: Double) {
        guard index < chunks.count else { return }
        chunks[index].verticalPosition = min(max(position, 0), 1)
        syncCaptionsToSectionEdit()
    }

    func splitCaption(at index: Int) {
        guard index < chunks.count else { return }
        let chunk = chunks[index]
        let mid = (chunk.startSeconds + chunk.endSeconds) / 2
        let words = chunk.text.split(separator: " ").map(String.init)
        let halfIdx = max(1, words.count / 2)
        let firstHalf = words.prefix(halfIdx).joined(separator: " ")
        let secondHalf = words.dropFirst(halfIdx).joined(separator: " ")

        chunks[index] = EditableCaptionChunk(
            text: firstHalf.isEmpty ? chunk.text : firstHalf,
            startSeconds: chunk.startSeconds,
            endSeconds: mid,
            verticalPosition: chunk.verticalPosition
        )
        chunks.insert(EditableCaptionChunk(
            text: secondHalf.isEmpty ? chunk.text : secondHalf,
            startSeconds: mid,
            endSeconds: chunk.endSeconds,
            verticalPosition: chunk.verticalPosition
        ), at: index + 1)
        syncCaptionsToSectionEdit()
    }

    func deleteCaption(at index: Int) {
        guard index < chunks.count else { return }
        chunks.remove(at: index)
        syncCaptionsToSectionEdit()
    }

    // MARK: - Composition

    /// Flattens rolls to a TimelineSegment and builds AVPlayerItem.
    func rebuildComposition() {
        buildTask?.cancel()
        buildTask = Task { @MainActor in
            do {
                let result = try await LiveCompositionBuilder.build(sectionEdit: sectionEdit)
                let item = AVPlayerItem(asset: result.composition)
                item.videoComposition = result.videoComposition
                item.audioMix = result.audioMix

                let wasPlaying = isPlaying
                let savedTime = currentTime
                player.replaceCurrentItem(with: item)
                seek(to: savedTime)
                if wasPlaying { player.play() }

                let compDuration = try await result.composition.load(.duration).seconds
                if compDuration > 0 { duration = compDuration }
            } catch {
                // Fallback: if no rolls/layers, just show empty
            }
        }
    }

    // MARK: - Grid Snapping

    func snapToGrid(_ rect: NormalizedRect) -> NormalizedRect {
        guard showGrid else { return rect }
        let snapThreshold = 0.02
        var snapped = rect

        let thirds: [Double] = [0, 1.0 / 3.0, 2.0 / 3.0, 1.0]
        for third in thirds {
            if abs(snapped.x - third) < snapThreshold { snapped.x = third }
            if abs(snapped.y - third) < snapThreshold { snapped.y = third }
            if abs(snapped.x + snapped.width - third) < snapThreshold {
                snapped.x = third - snapped.width
            }
            if abs(snapped.y + snapped.height - third) < snapThreshold {
                snapped.y = third - snapped.height
            }
        }
        snapped.x = max(0, min(1 - snapped.width, snapped.x))
        snapped.y = max(0, min(1 - snapped.height, snapped.y))

        return snapped
    }

    // MARK: - Private

    private func syncCaptionsToSectionEdit() {
        sectionEdit.captionTimestamps = chunks.map { chunk in
            CaptionTimestamp(
                text: chunk.text,
                startSeconds: chunk.startSeconds,
                endSeconds: chunk.endSeconds,
                verticalPosition: chunk.verticalPosition,
                style: captionStyle
            )
        }
        rebuildComposition()
    }

    private func updateStatus() {
        let hasLayersInRolls = sectionEdit.rolls.contains { !$0.layers.isEmpty }
        if !sectionEdit.captionTimestamps.isEmpty && hasLayersInRolls {
            sectionEdit.status = .captioned
        } else if hasLayersInRolls {
            sectionEdit.status = .arranged
        } else if !sectionEdit.marks.isEmpty {
            sectionEdit.status = .marked
        } else if !sectionEdit.mediaBin.isEmpty {
            sectionEdit.status = .hasMedia
        } else {
            sectionEdit.status = .empty
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
}
