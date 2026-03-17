import Foundation

/// Dual-write bridge that keeps legacy ScriptSection/Recording in sync with SectionEdit.
/// This allows new UI to write to SectionEdit while legacy views continue working.
enum SectionEditBridge {

    // MARK: - Migration: Legacy → SectionEdit

    /// Creates a SectionEdit from a legacy ScriptSection.
    static func migrate(from section: ScriptSection) -> SectionEdit {
        var edit = SectionEdit(scriptText: section.text)
        edit.id = section.id  // Preserve ID for dual-write lookups

        if let recording = section.recording {
            // Add the recording as a SourceMedia in the bin
            let source = SourceMedia(
                url: recording.rawVideoURL,
                type: .video,
                durationSeconds: recording.durationSeconds
            )
            edit.mediaBin = [source]

            // Create a mark covering the trimmed range (or full duration)
            let markIn = recording.trimStartSeconds ?? 0
            let markOut = recording.trimEndSeconds ?? recording.durationSeconds
            let mark = Mark(
                sourceMediaID: source.id,
                inSeconds: markIn,
                outSeconds: markOut
            )
            edit.marks = [mark]

            // Create an A-roll with the mark as a layer
            var aRollLayer = RollLayer(
                markID: mark.id,
                layer: Layer(
                    type: .video,
                    sourceURL: recording.rawVideoURL,
                    zIndex: 0,
                    trimStartSeconds: recording.trimStartSeconds,
                    trimEndSeconds: recording.trimEndSeconds,
                    hasBackgroundRemoval: recording.backgroundMediaURL != nil
                )
            )
            // If there was background removal, carry over the background media
            if let bgURL = recording.backgroundMediaURL {
                aRollLayer.layer.cachedProcessedURL = bgURL
            }

            let aRoll = Roll(
                name: "A-Roll",
                startOffset: 0,
                duration: mark.duration,
                layers: [aRollLayer]
            )
            edit.rolls = [aRoll]

            // Migrate captions
            edit.captionTimestamps = recording.captionTimestamps

            // Map status
            switch section.status {
            case .unrecorded:
                edit.status = .empty
            case .recorded:
                edit.status = .hasMedia
            case .processed:
                edit.status = .arranged
            case .exported:
                edit.status = .exported
            }
        }

        return edit
    }

    // MARK: - Sync: SectionEdit → Legacy

    /// Updates a ScriptSection + Recording from a SectionEdit, so legacy views stay working.
    static func syncToLegacy(from edit: SectionEdit, sectionID: UUID, projectID: UUID) -> ScriptSection {
        var section = ScriptSection(index: 0, text: edit.scriptText)
        section.id = sectionID
        section.previewThumbnailData = edit.previewThumbnailData

        // Map status back
        switch edit.status {
        case .empty:
            section.status = .unrecorded
        case .hasMedia, .marked:
            section.status = .recorded
        case .arranged, .captioned:
            section.status = .processed
        case .exported:
            section.status = .exported
        }

        // If we have media, create a Recording from the first source video
        if let firstVideo = edit.mediaBin.first(where: { $0.type == .video }) {
            var recording = Recording(
                sectionID: sectionID,
                rawVideoURL: firstVideo.url
            )
            recording.durationSeconds = firstVideo.durationSeconds
            recording.captionTimestamps = edit.captionTimestamps

            // Use first mark's trim points if available
            if let firstMark = edit.marks.first(where: { $0.sourceMediaID == firstVideo.id }) {
                recording.trimStartSeconds = firstMark.inSeconds > 0 ? firstMark.inSeconds : nil
                recording.trimEndSeconds = firstMark.outSeconds < firstVideo.durationSeconds ? firstMark.outSeconds : nil
            }

            section.recording = recording
        }

        return section
    }

    // MARK: - Add Media to SectionEdit

    /// Adds a recorded or imported video to a SectionEdit's media bin.
    static func addVideo(
        to edit: inout SectionEdit,
        url: URL,
        duration: Double,
        assetIdentifier: String? = nil,
        captionTimestamps: [CaptionTimestamp] = []
    ) {
        let source = SourceMedia(
            url: url,
            type: .video,
            durationSeconds: duration,
            assetIdentifier: assetIdentifier
        )
        edit.mediaBin.append(source)

        if !captionTimestamps.isEmpty {
            edit.captionTimestamps = captionTimestamps
        }

        // Auto-create a full-duration mark for the new video
        let mark = Mark(
            sourceMediaID: source.id,
            inSeconds: 0,
            outSeconds: duration
        )
        edit.marks.append(mark)

        // If this is the first video, auto-create an A-roll
        if edit.rolls.isEmpty {
            let rollLayer = RollLayer(
                markID: mark.id,
                layer: Layer(
                    type: .video,
                    sourceURL: url,
                    zIndex: 0
                )
            )
            let aRoll = Roll(
                name: "A-Roll",
                startOffset: 0,
                duration: duration,
                layers: [rollLayer]
            )
            edit.rolls = [aRoll]
        }

        edit.status = .hasMedia
    }

    /// Adds a photo to a SectionEdit's media bin.
    static func addPhoto(to edit: inout SectionEdit, url: URL, assetIdentifier: String? = nil) {
        let source = SourceMedia(
            url: url,
            type: .photo,
            assetIdentifier: assetIdentifier
        )
        edit.mediaBin.append(source)

        if edit.status == .empty {
            edit.status = .hasMedia
        }
    }
}
