import AVFoundation
import Foundation
import Observation
import Photos
import PhotosUI
import SwiftUI

@Observable
class MediaBinViewModel {
    var sectionEdit: SectionEdit
    let projectID: UUID
    let sectionID: UUID

    var isImporting = false
    var isRecording = false
    var error: String?

    init(sectionEdit: SectionEdit, projectID: UUID, sectionID: UUID) {
        self.sectionEdit = sectionEdit
        self.projectID = projectID
        self.sectionID = sectionID
    }

    var mediaBin: [SourceMedia] {
        sectionEdit.mediaBin
    }

    var hasMedia: Bool {
        !sectionEdit.mediaBin.isEmpty
    }

    // MARK: - Import Video

    func importVideo(from item: PhotosPickerItem) async {
        isImporting = true
        defer { isImporting = false }

        guard let movie = try? await item.loadTransferable(type: MovieTransferable.self) else {
            error = "Failed to load video"
            return
        }

        let destURL = VideoFileManager.mediaURL(
            projectID: projectID,
            sectionID: sectionID,
            mediaID: UUID()
        )
        try? FileManager.default.createDirectory(
            at: destURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: destURL)
        guard (try? FileManager.default.copyItem(at: movie.url, to: destURL)) != nil else {
            error = "Failed to save video"
            return
        }

        let asset = AVAsset(url: destURL)
        let duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0

        // Auto-generate captions from script text
        let words = sectionEdit.scriptText
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        let secondsPerWord = words.isEmpty ? 0 : duration / Double(words.count)
        let timestamps = words.enumerated().map { i, word in
            CaptionTimestamp(
                text: word,
                startSeconds: Double(i) * secondsPerWord,
                endSeconds: Double(i + 1) * secondsPerWord
            )
        }

        SectionEditBridge.addVideo(
            to: &sectionEdit,
            url: destURL,
            duration: duration,
            captionTimestamps: timestamps
        )
    }

    // MARK: - Import Photos

    func importPhotos(from items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let mediaID = UUID()
            let destURL = VideoFileManager.mediaURL(
                projectID: projectID,
                sectionID: sectionID,
                mediaID: mediaID
            ).deletingPathExtension().appendingPathExtension("jpg")
            try? FileManager.default.createDirectory(
                at: destURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: destURL)
            SectionEditBridge.addPhoto(to: &sectionEdit, url: destURL)
        }
    }

    // MARK: - Handle Recording Result

    func handleRecording(url: URL, duration: Double, captions: [CaptionTimestamp]) {
        SectionEditBridge.addVideo(
            to: &sectionEdit,
            url: url,
            duration: duration,
            captionTimestamps: captions
        )
    }

    // MARK: - Remove Media

    func removeMedia(_ media: SourceMedia) {
        sectionEdit.mediaBin.removeAll { $0.id == media.id }
        // Cascade: remove marks referencing this source
        let orphanMarkIDs = sectionEdit.marks
            .filter { $0.sourceMediaID == media.id }
            .map { $0.id }
        sectionEdit.marks.removeAll { $0.sourceMediaID == media.id }
        // Cascade: remove roll layers referencing orphaned marks
        for i in sectionEdit.rolls.indices {
            sectionEdit.rolls[i].layers.removeAll { rollLayer in
                guard let markID = rollLayer.markID else { return false }
                return orphanMarkIDs.contains(markID)
            }
        }
        // Update status
        if sectionEdit.mediaBin.isEmpty {
            sectionEdit.status = .empty
        }
    }
}
