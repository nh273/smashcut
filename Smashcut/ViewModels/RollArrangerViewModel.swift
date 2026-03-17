import AVFoundation
import Observation

@Observable
class RollArrangerViewModel {
    var sectionEdit: SectionEdit
    let projectID: UUID

    var selectedRollID: UUID?
    var selectedLayerID: UUID?

    init(sectionEdit: SectionEdit, projectID: UUID) {
        self.sectionEdit = sectionEdit
        self.projectID = projectID
    }

    var rolls: [Roll] {
        sectionEdit.rolls
    }

    var unusedMarks: [Mark] {
        let usedMarkIDs = Set(sectionEdit.rolls.flatMap { $0.layers.compactMap { $0.markID } })
        return sectionEdit.marks.filter { !usedMarkIDs.contains($0.id) }
    }

    /// Total section duration based on all rolls.
    var totalDuration: Double {
        sectionEdit.duration
    }

    // MARK: - Roll Management

    func addRoll(name: String = "B-Roll") {
        let offset = sectionEdit.rolls.map { $0.startOffset + $0.duration }.max() ?? 0
        let roll = Roll(name: name, startOffset: offset)
        sectionEdit.rolls.append(roll)
        selectedRollID = roll.id
    }

    func deleteRoll(_ roll: Roll) {
        sectionEdit.rolls.removeAll { $0.id == roll.id }
        if selectedRollID == roll.id {
            selectedRollID = nil
        }
        updateStatus()
    }

    func renameRoll(id: UUID, name: String) {
        guard let idx = sectionEdit.rolls.firstIndex(where: { $0.id == id }) else { return }
        sectionEdit.rolls[idx].name = name
    }

    func updateRollTiming(id: UUID, startOffset: Double, duration: Double) {
        guard let idx = sectionEdit.rolls.firstIndex(where: { $0.id == id }) else { return }
        sectionEdit.rolls[idx].startOffset = max(0, startOffset)
        sectionEdit.rolls[idx].duration = max(0.1, duration)
    }

    // MARK: - Add Mark to Roll

    func addMarkToRoll(markID: UUID, rollID: UUID) {
        guard let mark = sectionEdit.marks.first(where: { $0.id == markID }),
              let rollIdx = sectionEdit.rolls.firstIndex(where: { $0.id == rollID }) else { return }

        // Find the source media for the URL
        let sourceURL = sectionEdit.mediaBin.first(where: { $0.id == mark.sourceMediaID })?.url

        let rollLayer = RollLayer(
            markID: markID,
            layer: Layer(
                type: .video,
                sourceURL: sourceURL,
                zIndex: sectionEdit.rolls[rollIdx].layers.count,
                trimStartSeconds: mark.inSeconds,
                trimEndSeconds: mark.outSeconds
            )
        )
        sectionEdit.rolls[rollIdx].layers.append(rollLayer)

        // Update roll duration to match the mark if it was 0
        if sectionEdit.rolls[rollIdx].duration <= 0 {
            sectionEdit.rolls[rollIdx].duration = mark.duration
        }

        updateStatus()
    }

    func removeLayerFromRoll(rollID: UUID, layerID: UUID) {
        guard let rollIdx = sectionEdit.rolls.firstIndex(where: { $0.id == rollID }) else { return }
        sectionEdit.rolls[rollIdx].layers.removeAll { $0.id == layerID }
        // Remove empty rolls that aren't A-Roll
        if sectionEdit.rolls[rollIdx].layers.isEmpty && sectionEdit.rolls[rollIdx].name != "A-Roll" {
            sectionEdit.rolls.remove(at: rollIdx)
        }
        updateStatus()
    }

    // MARK: - Layer Position (spatial)

    func updateLayerPosition(rollID: UUID, layerID: UUID, position: NormalizedRect) {
        guard let rollIdx = sectionEdit.rolls.firstIndex(where: { $0.id == rollID }),
              let layerIdx = sectionEdit.rolls[rollIdx].layers.firstIndex(where: { $0.id == layerID }) else { return }
        sectionEdit.rolls[rollIdx].layers[layerIdx].layer.position = position
    }

    func updateLayerZIndex(rollID: UUID, layerID: UUID, zIndex: Int) {
        guard let rollIdx = sectionEdit.rolls.firstIndex(where: { $0.id == rollID }),
              let layerIdx = sectionEdit.rolls[rollIdx].layers.firstIndex(where: { $0.id == layerID }) else { return }
        sectionEdit.rolls[rollIdx].layers[layerIdx].layer.zIndex = zIndex
    }

    // MARK: - Flatten to TimelineSegment (for composition)

    /// Flattens rolls into a single TimelineSegment for the compositor.
    func flattenToSegment() -> TimelineSegment {
        var segment = TimelineSegment(scriptText: sectionEdit.scriptText)
        segment.duration = totalDuration

        var allLayers: [Layer] = []
        for roll in sectionEdit.rolls {
            for rollLayer in roll.layers {
                var layer = rollLayer.layer
                // Apply roll timing: offset the layer's startOffset by the roll's position
                layer.startOffset = roll.startOffset
                allLayers.append(layer)
            }
        }

        segment.layers = allLayers.sorted { $0.zIndex < $1.zIndex }

        // Carry over text layers from captions
        segment.textLayers = sectionEdit.captionTimestamps.map { ts in
            let baseLayer = Layer(
                type: .text,
                position: NormalizedRect(x: 0, y: ts.verticalPosition, width: 1, height: 0.1),
                zIndex: 100
            )
            return TextLayer(
                layer: baseLayer,
                text: ts.text,
                style: ts.style,
                startSeconds: ts.startSeconds,
                endSeconds: ts.endSeconds
            )
        }

        return segment
    }

    // MARK: - Private

    private func updateStatus() {
        let hasLayersInRolls = sectionEdit.rolls.contains { !$0.layers.isEmpty }
        if hasLayersInRolls {
            sectionEdit.status = .arranged
        } else if !sectionEdit.marks.isEmpty {
            sectionEdit.status = .marked
        } else if !sectionEdit.mediaBin.isEmpty {
            sectionEdit.status = .hasMedia
        } else {
            sectionEdit.status = .empty
        }
    }
}
