import Foundation
import Observation
import PhotosUI
import SwiftUI

@Observable
class BackgroundEditorViewModel {
    var section: ScriptSection
    var projectID: UUID

    var selectedItem: PhotosPickerItem?
    var backgroundImage: UIImage?
    var backgroundVideoURL: URL?
    var isVideo = false

    var isProcessing = false
    var processingProgress: Double = 0
    var processingError: String?
    var processingComplete = false

    init(section: ScriptSection, projectID: UUID) {
        self.section = section
        self.projectID = projectID
    }

    func loadSelectedMedia() async {
        guard let item = selectedItem else { return }

        // Try image first
        if let data = try? await item.loadTransferable(type: Data.self) {
            if let image = UIImage(data: data) {
                await MainActor.run {
                    self.backgroundImage = image
                    self.isVideo = false
                    self.backgroundVideoURL = nil
                }
                // Save to app support
                let ext = "jpg"
                let url = VideoFileManager.backgroundMediaURL(projectID: projectID, sectionID: section.id, ext: ext)
                try? data.write(to: url)
                await MainActor.run {
                    if var recording = self.section.recording {
                        recording.backgroundMediaURL = url
                        recording.backgroundIsVideo = false
                        self.section.recording = recording
                    }
                }
                return
            }
        }

        // Try video
        if let movie = try? await item.loadTransferable(type: URL.self) {
            let ext = movie.pathExtension
            let url = VideoFileManager.backgroundMediaURL(projectID: projectID, sectionID: section.id, ext: ext)
            try? FileManager.default.copyItem(at: movie, to: url)
            await MainActor.run {
                self.backgroundVideoURL = url
                self.isVideo = true
                self.backgroundImage = nil
                if var recording = self.section.recording {
                    recording.backgroundMediaURL = url
                    recording.backgroundIsVideo = true
                    self.section.recording = recording
                }
            }
        }
    }

    func processBackground() async {
        guard let recording = section.recording else {
            processingError = "No recording found for this section."
            return
        }

        isProcessing = true
        processingProgress = 0
        processingError = nil

        let outputURL = VideoFileManager.maskedVideoURL(projectID: projectID, sectionID: section.id)

        do {
            try await SegmentationService.shared.processVideo(
                inputURL: recording.rawVideoURL,
                backgroundURL: recording.backgroundMediaURL,
                backgroundIsVideo: recording.backgroundIsVideo,
                outputURL: outputURL,
                progressHandler: { [weak self] progress in
                    Task { @MainActor in
                        self?.processingProgress = progress
                    }
                }
            )

            await MainActor.run {
                if var rec = self.section.recording {
                    rec.processedVideoURL = outputURL
                    rec.compositeVideoURL = outputURL
                    self.section.recording = rec
                }
                self.section.status = .processed
                self.isProcessing = false
                self.processingComplete = true
            }
        } catch {
            await MainActor.run {
                self.processingError = error.localizedDescription
                self.isProcessing = false
            }
        }
    }
}
