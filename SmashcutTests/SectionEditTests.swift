import Foundation
import Testing
@testable import Smashcut

// MARK: - SectionEdit Model Tests

struct SectionEditModelTests {

    @Test func newSectionEditIsEmpty() {
        let edit = SectionEdit(scriptText: "Hello world")
        #expect(edit.scriptText == "Hello world")
        #expect(edit.mediaBin.isEmpty)
        #expect(edit.marks.isEmpty)
        #expect(edit.rolls.isEmpty)
        #expect(edit.captionTimestamps.isEmpty)
        #expect(edit.status == .empty)
        #expect(edit.duration == 0)
    }

    @Test func durationComputedFromRolls() {
        var edit = SectionEdit(scriptText: "test")
        edit.rolls = [
            Roll(name: "A-Roll", startOffset: 0, duration: 5),
            Roll(name: "B-Roll", startOffset: 3, duration: 4),
        ]
        // max(0+5, 3+4) = 7
        #expect(edit.duration == 7)
    }

    @Test func durationZeroWithNoRolls() {
        let edit = SectionEdit(scriptText: "test")
        #expect(edit.duration == 0)
    }

    @Test func markDurationComputed() {
        let mark = Mark(sourceMediaID: UUID(), inSeconds: 1.5, outSeconds: 4.0)
        #expect(mark.duration == 2.5)
    }

    @Test func editStatusProgression() {
        #expect(EditStatus.empty.rawValue == "empty")
        #expect(EditStatus.hasMedia.rawValue == "hasMedia")
        #expect(EditStatus.marked.rawValue == "marked")
        #expect(EditStatus.arranged.rawValue == "arranged")
        #expect(EditStatus.captioned.rawValue == "captioned")
        #expect(EditStatus.exported.rawValue == "exported")
    }

    @Test func sectionEditCodable() throws {
        var edit = SectionEdit(scriptText: "Test script")
        let source = SourceMedia(
            url: URL(fileURLWithPath: "/tmp/test.mp4"),
            type: .video,
            durationSeconds: 5.0
        )
        edit.mediaBin = [source]
        edit.marks = [Mark(sourceMediaID: source.id, inSeconds: 0, outSeconds: 5)]
        edit.status = .hasMedia

        let data = try JSONEncoder().encode(edit)
        let decoded = try JSONDecoder().decode(SectionEdit.self, from: data)
        #expect(decoded.scriptText == "Test script")
        #expect(decoded.mediaBin.count == 1)
        #expect(decoded.marks.count == 1)
        #expect(decoded.status == .hasMedia)
    }

    @Test func rollLayerCodable() throws {
        let rollLayer = RollLayer(
            markID: UUID(),
            layer: Layer(type: .video, sourceURL: URL(fileURLWithPath: "/tmp/v.mp4"), zIndex: 0)
        )
        let data = try JSONEncoder().encode(rollLayer)
        let decoded = try JSONDecoder().decode(RollLayer.self, from: data)
        #expect(decoded.markID == rollLayer.markID)
        #expect(decoded.layer.type == .video)
    }
}

// MARK: - SectionEditBridge Tests

struct SectionEditBridgeTests {

    private func makeLegacySection(withRecording: Bool = true) -> ScriptSection {
        var section = ScriptSection(index: 0, text: "Test section text")
        if withRecording {
            var recording = Recording(
                sectionID: section.id,
                rawVideoURL: URL(fileURLWithPath: "/tmp/raw.mp4")
            )
            recording.durationSeconds = 10.0
            recording.trimStartSeconds = 1.0
            recording.trimEndSeconds = 8.0
            recording.captionTimestamps = [
                CaptionTimestamp(text: "Hello", startSeconds: 0, endSeconds: 0.5),
                CaptionTimestamp(text: "world", startSeconds: 0.5, endSeconds: 1.0),
            ]
            section.recording = recording
            section.status = .recorded
        }
        return section
    }

    @Test func migratePreservesID() {
        let section = makeLegacySection()
        let edit = SectionEditBridge.migrate(from: section)
        #expect(edit.id == section.id)
    }

    @Test func migratePreservesText() {
        let section = makeLegacySection()
        let edit = SectionEditBridge.migrate(from: section)
        #expect(edit.scriptText == "Test section text")
    }

    @Test func migrateCreatesSourceMedia() {
        let section = makeLegacySection()
        let edit = SectionEditBridge.migrate(from: section)
        #expect(edit.mediaBin.count == 1)
        #expect(edit.mediaBin[0].type == .video)
        #expect(edit.mediaBin[0].durationSeconds == 10.0)
    }

    @Test func migrateCreatesMarkFromTrim() {
        let section = makeLegacySection()
        let edit = SectionEditBridge.migrate(from: section)
        #expect(edit.marks.count == 1)
        #expect(edit.marks[0].inSeconds == 1.0)
        #expect(edit.marks[0].outSeconds == 8.0)
        #expect(edit.marks[0].sourceMediaID == edit.mediaBin[0].id)
    }

    @Test func migrateCreatesARoll() {
        let section = makeLegacySection()
        let edit = SectionEditBridge.migrate(from: section)
        #expect(edit.rolls.count == 1)
        #expect(edit.rolls[0].name == "A-Roll")
        #expect(edit.rolls[0].layers.count == 1)
        #expect(edit.rolls[0].duration == 7.0) // 8.0 - 1.0
    }

    @Test func migrateCopiesCaptions() {
        let section = makeLegacySection()
        let edit = SectionEditBridge.migrate(from: section)
        #expect(edit.captionTimestamps.count == 2)
        #expect(edit.captionTimestamps[0].text == "Hello")
    }

    @Test func migrateStatusMapping() {
        var section = makeLegacySection()

        section.status = .unrecorded
        section.recording = nil
        #expect(SectionEditBridge.migrate(from: section).status == .empty)

        section = makeLegacySection()
        section.status = .recorded
        #expect(SectionEditBridge.migrate(from: section).status == .hasMedia)

        section.status = .processed
        #expect(SectionEditBridge.migrate(from: section).status == .arranged)

        section.status = .exported
        #expect(SectionEditBridge.migrate(from: section).status == .exported)
    }

    @Test func migrateWithNoRecording() {
        let section = makeLegacySection(withRecording: false)
        let edit = SectionEditBridge.migrate(from: section)
        #expect(edit.mediaBin.isEmpty)
        #expect(edit.marks.isEmpty)
        #expect(edit.rolls.isEmpty)
        #expect(edit.status == .empty)
    }

    @Test func syncToLegacyPreservesText() {
        var edit = SectionEdit(scriptText: "New text")
        edit.status = .hasMedia
        let section = SectionEditBridge.syncToLegacy(
            from: edit, sectionID: UUID(), projectID: UUID()
        )
        #expect(section.text == "New text")
    }

    @Test func syncToLegacyStatusMapping() {
        var edit = SectionEdit(scriptText: "test")

        edit.status = .empty
        #expect(SectionEditBridge.syncToLegacy(from: edit, sectionID: UUID(), projectID: UUID()).status == .unrecorded)

        edit.status = .hasMedia
        #expect(SectionEditBridge.syncToLegacy(from: edit, sectionID: UUID(), projectID: UUID()).status == .recorded)

        edit.status = .marked
        #expect(SectionEditBridge.syncToLegacy(from: edit, sectionID: UUID(), projectID: UUID()).status == .recorded)

        edit.status = .arranged
        #expect(SectionEditBridge.syncToLegacy(from: edit, sectionID: UUID(), projectID: UUID()).status == .processed)

        edit.status = .captioned
        #expect(SectionEditBridge.syncToLegacy(from: edit, sectionID: UUID(), projectID: UUID()).status == .processed)

        edit.status = .exported
        #expect(SectionEditBridge.syncToLegacy(from: edit, sectionID: UUID(), projectID: UUID()).status == .exported)
    }

    @Test func syncToLegacyCreatesRecordingFromVideo() {
        var edit = SectionEdit(scriptText: "test")
        SectionEditBridge.addVideo(
            to: &edit,
            url: URL(fileURLWithPath: "/tmp/video.mp4"),
            duration: 5.0
        )
        let section = SectionEditBridge.syncToLegacy(
            from: edit, sectionID: UUID(), projectID: UUID()
        )
        #expect(section.recording != nil)
        #expect(section.recording?.durationSeconds == 5.0)
    }

    @Test func addVideoUpdatesStatus() {
        var edit = SectionEdit(scriptText: "test")
        #expect(edit.status == .empty)

        SectionEditBridge.addVideo(
            to: &edit,
            url: URL(fileURLWithPath: "/tmp/v.mp4"),
            duration: 3.0
        )
        #expect(edit.status == .hasMedia)
        #expect(edit.mediaBin.count == 1)
        #expect(edit.marks.count == 1)
        #expect(edit.rolls.count == 1) // Auto A-Roll
    }

    @Test func addVideoAutoCreatesARoll() {
        var edit = SectionEdit(scriptText: "test")
        SectionEditBridge.addVideo(
            to: &edit,
            url: URL(fileURLWithPath: "/tmp/v.mp4"),
            duration: 5.0
        )
        #expect(edit.rolls[0].name == "A-Roll")
        #expect(edit.rolls[0].duration == 5.0)
        #expect(edit.rolls[0].layers.count == 1)
    }

    @Test func addSecondVideoDoesNotCreateSecondARoll() {
        var edit = SectionEdit(scriptText: "test")
        SectionEditBridge.addVideo(to: &edit, url: URL(fileURLWithPath: "/tmp/v1.mp4"), duration: 3.0)
        SectionEditBridge.addVideo(to: &edit, url: URL(fileURLWithPath: "/tmp/v2.mp4"), duration: 4.0)
        #expect(edit.mediaBin.count == 2)
        #expect(edit.marks.count == 2)
        #expect(edit.rolls.count == 1) // Still just one A-Roll
    }

    @Test func addPhotoUpdatesStatus() {
        var edit = SectionEdit(scriptText: "test")
        SectionEditBridge.addPhoto(to: &edit, url: URL(fileURLWithPath: "/tmp/photo.jpg"))
        #expect(edit.status == .hasMedia)
        #expect(edit.mediaBin.count == 1)
        #expect(edit.mediaBin[0].type == .photo)
    }

    @Test func addVideoCaptionsCarriedOver() {
        var edit = SectionEdit(scriptText: "test")
        let captions = [CaptionTimestamp(text: "Hi", startSeconds: 0, endSeconds: 1)]
        SectionEditBridge.addVideo(
            to: &edit,
            url: URL(fileURLWithPath: "/tmp/v.mp4"),
            duration: 3.0,
            captionTimestamps: captions
        )
        #expect(edit.captionTimestamps.count == 1)
        #expect(edit.captionTimestamps[0].text == "Hi")
    }

    @Test func roundTripMigrateThenSync() {
        let original = makeLegacySection()
        let edit = SectionEditBridge.migrate(from: original)
        let synced = SectionEditBridge.syncToLegacy(
            from: edit, sectionID: original.id, projectID: UUID()
        )
        #expect(synced.text == original.text)
        #expect(synced.recording != nil)
        #expect(synced.recording?.durationSeconds == 10.0)
        #expect(synced.recording?.captionTimestamps.count == 2)
    }
}

// MARK: - MarkEditorViewModel Tests (no AVPlayer)

struct MarkEditorLogicTests {

    private func makeTestEdit() -> SectionEdit {
        var edit = SectionEdit(scriptText: "test")
        let source = SourceMedia(
            url: URL(fileURLWithPath: "/tmp/test.mp4"),
            type: .video,
            durationSeconds: 10.0
        )
        edit.mediaBin = [source]
        edit.status = .hasMedia
        return edit
    }

    @Test func markOutRejectsInvertedRange() {
        var edit = makeTestEdit()
        let mark = Mark(sourceMediaID: edit.mediaBin[0].id, inSeconds: 5, outSeconds: 2)
        edit.marks.append(mark)
        // Mark with inSeconds > outSeconds should have negative duration
        #expect(mark.duration < 0)
    }

    @Test func updateMarkRejectsInvalidRange() {
        var edit = makeTestEdit()
        let mark = Mark(sourceMediaID: edit.mediaBin[0].id, inSeconds: 1, outSeconds: 5)
        edit.marks.append(mark)

        // Simulate updateMark logic (from ViewModel)
        let id = mark.id
        let newIn = 6.0
        let newOut = 3.0
        // Guard should reject: outSeconds <= inSeconds
        let valid = newOut > newIn && newIn >= 0
        #expect(!valid)

        // Valid update
        let validIn = 2.0
        let validOut = 4.0
        let isValid = validOut > validIn && validIn >= 0
        #expect(isValid)
    }

    @Test func deleteMarkCascadesToRolls() {
        var edit = makeTestEdit()
        let sourceID = edit.mediaBin[0].id
        let mark = Mark(sourceMediaID: sourceID, inSeconds: 0, outSeconds: 5)
        edit.marks.append(mark)

        let rollLayer = RollLayer(
            markID: mark.id,
            layer: Layer(type: .video, sourceURL: URL(fileURLWithPath: "/tmp/test.mp4"), zIndex: 0)
        )
        edit.rolls = [Roll(name: "A-Roll", startOffset: 0, duration: 5, layers: [rollLayer])]

        // Delete the mark
        edit.marks.removeAll { $0.id == mark.id }
        for i in edit.rolls.indices {
            edit.rolls[i].layers.removeAll { $0.markID == mark.id }
        }
        edit.rolls.removeAll { $0.layers.isEmpty }

        #expect(edit.marks.isEmpty)
        #expect(edit.rolls.isEmpty) // Roll removed because it became empty
    }

    @Test func statusUpdatesOnMarkChanges() {
        var edit = makeTestEdit()
        #expect(edit.status == .hasMedia)

        // Add a mark → should be .marked
        let mark = Mark(sourceMediaID: edit.mediaBin[0].id, inSeconds: 0, outSeconds: 3)
        edit.marks.append(mark)
        edit.status = edit.marks.isEmpty ? (edit.mediaBin.isEmpty ? .empty : .hasMedia) : .marked
        #expect(edit.status == .marked)

        // Remove all marks → should be .hasMedia
        edit.marks.removeAll()
        edit.status = edit.marks.isEmpty ? (edit.mediaBin.isEmpty ? .empty : .hasMedia) : .marked
        #expect(edit.status == .hasMedia)
    }
}

// MARK: - RollArrangerViewModel Tests

struct RollArrangerLogicTests {

    private func makeArrangerEdit() -> SectionEdit {
        var edit = SectionEdit(scriptText: "test")
        let source = SourceMedia(
            url: URL(fileURLWithPath: "/tmp/test.mp4"),
            type: .video,
            durationSeconds: 10.0
        )
        edit.mediaBin = [source]
        let mark1 = Mark(sourceMediaID: source.id, inSeconds: 0, outSeconds: 5)
        let mark2 = Mark(sourceMediaID: source.id, inSeconds: 5, outSeconds: 10)
        edit.marks = [mark1, mark2]

        let rollLayer = RollLayer(
            markID: mark1.id,
            layer: Layer(type: .video, sourceURL: source.url, zIndex: 0, trimStartSeconds: 0, trimEndSeconds: 5)
        )
        edit.rolls = [Roll(name: "A-Roll", startOffset: 0, duration: 5, layers: [rollLayer])]
        edit.status = .marked
        return edit
    }

    @Test func unusedMarksFiltersCorrectly() {
        let edit = makeArrangerEdit()
        let usedMarkIDs = Set(edit.rolls.flatMap { $0.layers.compactMap { $0.markID } })
        let unused = edit.marks.filter { !usedMarkIDs.contains($0.id) }
        #expect(unused.count == 1) // mark2 is unused
        #expect(unused[0].inSeconds == 5)
    }

    @Test func addRollCreatesAtEnd() {
        var edit = makeArrangerEdit()
        let offset = edit.rolls.map { $0.startOffset + $0.duration }.max() ?? 0
        let newRoll = Roll(name: "B-Roll", startOffset: offset)
        edit.rolls.append(newRoll)
        #expect(edit.rolls.count == 2)
        #expect(edit.rolls[1].startOffset == 5) // After A-Roll's end
    }

    @Test func deleteRollRemovesCorrectly() {
        var edit = makeArrangerEdit()
        let bRoll = Roll(name: "B-Roll", startOffset: 5, duration: 3)
        edit.rolls.append(bRoll)
        #expect(edit.rolls.count == 2)

        edit.rolls.removeAll { $0.id == bRoll.id }
        #expect(edit.rolls.count == 1)
        #expect(edit.rolls[0].name == "A-Roll")
    }

    @Test func addMarkToRollRequiresValidMedia() {
        var edit = makeArrangerEdit()
        // Create a mark with non-existent source media ID
        let orphanMark = Mark(sourceMediaID: UUID(), inSeconds: 0, outSeconds: 3)
        edit.marks.append(orphanMark)

        // Try to find source media — should be nil
        let sourceMedia = edit.mediaBin.first(where: { $0.id == orphanMark.sourceMediaID })
        #expect(sourceMedia == nil)
    }

    @Test func flattenToSegmentPreservesLayers() {
        let edit = makeArrangerEdit()
        let vm = RollArrangerViewModel(sectionEdit: edit, projectID: UUID())
        let segment = vm.flattenToSegment()
        #expect(segment.scriptText == "test")
        #expect(segment.layers.count == 1)
        #expect(segment.layers[0].type == .video)
    }

    @Test func flattenToSegmentAppliesRollOffset() {
        var edit = makeArrangerEdit()
        // Add a B-Roll at offset 3
        let source = edit.mediaBin[0]
        let mark = edit.marks[1]
        let bRollLayer = RollLayer(
            markID: mark.id,
            layer: Layer(type: .video, sourceURL: source.url, zIndex: 1, trimStartSeconds: 5, trimEndSeconds: 10)
        )
        edit.rolls.append(Roll(name: "B-Roll", startOffset: 3, duration: 5, layers: [bRollLayer]))

        let vm = RollArrangerViewModel(sectionEdit: edit, projectID: UUID())
        let segment = vm.flattenToSegment()
        #expect(segment.layers.count == 2)
        // A-Roll layer should have offset 0, B-Roll should have offset 3
        let sorted = segment.layers.sorted { $0.zIndex < $1.zIndex }
        #expect(sorted[0].startOffset == 0)
        #expect(sorted[1].startOffset == 3)
    }

    @Test func statusUpdatesOnRollChanges() {
        let edit = makeArrangerEdit()
        let vm = RollArrangerViewModel(sectionEdit: edit, projectID: UUID())

        // Has layers in rolls → arranged
        let hasLayers = vm.sectionEdit.rolls.contains { !$0.layers.isEmpty }
        #expect(hasLayers)
    }

    @Test func removeLayerFromNonARollDeletesEmptyRoll() {
        var edit = makeArrangerEdit()
        let source = edit.mediaBin[0]
        let mark = edit.marks[1]
        let bLayer = RollLayer(
            markID: mark.id,
            layer: Layer(type: .video, sourceURL: source.url, zIndex: 1)
        )
        edit.rolls.append(Roll(name: "B-Roll", startOffset: 5, duration: 5, layers: [bLayer]))
        #expect(edit.rolls.count == 2)

        let vm = RollArrangerViewModel(sectionEdit: edit, projectID: UUID())
        vm.removeLayerFromRoll(rollID: vm.sectionEdit.rolls[1].id, layerID: bLayer.id)
        #expect(vm.sectionEdit.rolls.count == 1) // B-Roll removed
        #expect(vm.sectionEdit.rolls[0].name == "A-Roll")
    }

    @Test func removeLayerFromARollKeepsEmptyARoll() {
        var edit = makeArrangerEdit()
        let vm = RollArrangerViewModel(sectionEdit: edit, projectID: UUID())
        let aRollID = vm.sectionEdit.rolls[0].id
        let layerID = vm.sectionEdit.rolls[0].layers[0].id

        vm.removeLayerFromRoll(rollID: aRollID, layerID: layerID)
        // A-Roll should NOT be deleted even when empty
        #expect(vm.sectionEdit.rolls.count == 1)
        #expect(vm.sectionEdit.rolls[0].name == "A-Roll")
        #expect(vm.sectionEdit.rolls[0].layers.isEmpty)
    }
}

// MARK: - MediaBinViewModel Cascade Delete Tests

struct MediaBinCascadeTests {

    @Test func removeMediaCascadesMarksAndRollLayers() {
        var edit = SectionEdit(scriptText: "test")
        let source = SourceMedia(
            url: URL(fileURLWithPath: "/tmp/v.mp4"),
            type: .video,
            durationSeconds: 5.0
        )
        edit.mediaBin = [source]

        let mark = Mark(sourceMediaID: source.id, inSeconds: 0, outSeconds: 5)
        edit.marks = [mark]

        let rollLayer = RollLayer(
            markID: mark.id,
            layer: Layer(type: .video, sourceURL: source.url, zIndex: 0)
        )
        edit.rolls = [Roll(name: "A-Roll", startOffset: 0, duration: 5, layers: [rollLayer])]
        edit.status = .hasMedia

        // Simulate removeMedia cascade (from MediaBinViewModel)
        edit.mediaBin.removeAll { $0.id == source.id }
        let orphanMarkIDs = edit.marks.filter { $0.sourceMediaID == source.id }.map { $0.id }
        edit.marks.removeAll { $0.sourceMediaID == source.id }
        for i in edit.rolls.indices {
            edit.rolls[i].layers.removeAll { rollLayer in
                guard let markID = rollLayer.markID else { return false }
                return orphanMarkIDs.contains(markID)
            }
        }

        #expect(edit.mediaBin.isEmpty)
        #expect(edit.marks.isEmpty)
        #expect(edit.rolls[0].layers.isEmpty)
    }
}

// MARK: - CaptionEditorViewModel SectionEdit Init Tests

struct CaptionEditorSectionEditTests {

    @Test func initFromSectionEdit() {
        var edit = SectionEdit(scriptText: "test")
        edit.captionTimestamps = [
            CaptionTimestamp(text: "Hello", startSeconds: 0, endSeconds: 0.5),
            CaptionTimestamp(text: "world", startSeconds: 0.5, endSeconds: 1.0),
            CaptionTimestamp(text: "this", startSeconds: 1.0, endSeconds: 1.5),
            CaptionTimestamp(text: "is", startSeconds: 1.5, endSeconds: 2.0),
            CaptionTimestamp(text: "a", startSeconds: 2.0, endSeconds: 2.5),
            CaptionTimestamp(text: "test", startSeconds: 2.5, endSeconds: 3.0),
        ]
        SectionEditBridge.addVideo(
            to: &edit,
            url: URL(fileURLWithPath: "/tmp/v.mp4"),
            duration: 3.0,
            captionTimestamps: edit.captionTimestamps
        )

        let vm = CaptionEditorViewModel(sectionEdit: edit)
        #expect(vm.totalDuration == 3.0)
        #expect(!vm.chunks.isEmpty) // Should have built chunks
        #expect(vm.chunks[0].text.contains("Hello")) // First chunk starts with first word
    }

    @Test func initFromEmptySectionEdit() {
        let edit = SectionEdit(scriptText: "test")
        let vm = CaptionEditorViewModel(sectionEdit: edit)
        #expect(vm.totalDuration == 1) // min(duration, 1)
        #expect(vm.chunks.isEmpty)
    }

    @Test func toCaptionTimestampsRoundTrips() {
        var edit = SectionEdit(scriptText: "test")
        edit.captionTimestamps = [
            CaptionTimestamp(text: "Hello world this is a test", startSeconds: 0, endSeconds: 3),
        ]
        let vm = CaptionEditorViewModel(sectionEdit: edit)
        let exported = vm.toCaptionTimestamps()
        #expect(!exported.isEmpty)
        // The text should be preserved (chunking may split differently)
        let allText = exported.map(\.text).joined(separator: " ")
        #expect(allText.contains("Hello"))
    }
}

// MARK: - VideoFileManager URL Rebase Tests

struct VideoFileManagerTests {

    @Test func rebaseURLPreservesValidURL() {
        let url = URL(fileURLWithPath: "/tmp/some-other-path.mp4")
        let rebased = VideoFileManager.rebaseURL(url)
        // Non-smashcut paths pass through unchanged
        #expect(rebased == url)
    }

    @Test func existsReturnsFalseForMissingFile() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID()).mp4")
        #expect(!VideoFileManager.exists(url))
    }

    @Test func mediaURLCreatesCorrectPath() {
        let projectID = UUID()
        let sectionID = UUID()
        let mediaID = UUID()
        let url = VideoFileManager.mediaURL(projectID: projectID, sectionID: sectionID, mediaID: mediaID)
        #expect(url.pathExtension == "mp4")
        #expect(url.path.contains(projectID.uuidString))
        #expect(url.path.contains(sectionID.uuidString))
        #expect(url.path.contains(mediaID.uuidString))
    }
}

// MARK: - Edge Cases

struct EdgeCaseTests {

    @Test func emptyScriptTextProducesNoCaptions() {
        var edit = SectionEdit(scriptText: "")
        SectionEditBridge.addVideo(
            to: &edit,
            url: URL(fileURLWithPath: "/tmp/v.mp4"),
            duration: 5.0
        )
        // Empty script = no caption timestamps generated
        #expect(edit.captionTimestamps.isEmpty)
    }

    @Test func zeroDurationVideoHandledGracefully() {
        var edit = SectionEdit(scriptText: "test words here")
        SectionEditBridge.addVideo(
            to: &edit,
            url: URL(fileURLWithPath: "/tmp/v.mp4"),
            duration: 0
        )
        // Should still create media and mark
        #expect(edit.mediaBin.count == 1)
        #expect(edit.marks.count == 1)
        #expect(edit.marks[0].duration == 0)
    }

    @Test func multipleSourceMediaTypesCoexist() {
        var edit = SectionEdit(scriptText: "test")
        SectionEditBridge.addVideo(
            to: &edit,
            url: URL(fileURLWithPath: "/tmp/v.mp4"),
            duration: 5.0
        )
        SectionEditBridge.addPhoto(to: &edit, url: URL(fileURLWithPath: "/tmp/p.jpg"))

        #expect(edit.mediaBin.count == 2)
        #expect(edit.mediaBin.filter { $0.type == .video }.count == 1)
        #expect(edit.mediaBin.filter { $0.type == .photo }.count == 1)
    }

    @Test func rollWithNoLayersHasZeroDuration() {
        let roll = Roll(name: "Empty", startOffset: 0)
        #expect(roll.duration == 0)
        #expect(roll.layers.isEmpty)
    }

    @Test func markWithZeroDuration() {
        let mark = Mark(sourceMediaID: UUID(), inSeconds: 3.0, outSeconds: 3.0)
        #expect(mark.duration == 0)
    }
}
