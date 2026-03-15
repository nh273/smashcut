import AVFoundation
import PhotosUI
import SwiftUI

struct SectionRowView: View {
    let section: ScriptSection
    let project: Project

    @Environment(AppState.self) private var appState
    @State private var importItem: PhotosPickerItem?
    @State private var isImporting = false

    // Navigation state — one @State per destination prevents simultaneous firing
    @State private var navigateToRecord = false
    @State private var navigateToCaptionEditor = false
    @State private var navigateToTrim = false
    @State private var navigateToBackground = false
    @State private var navigateToRerecord = false
    @State private var navigateToExport = false
    @State private var navigateToReprocess = false
    @State private var showRefineSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Section \(section.index + 1)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                StatusBadge(status: section.status)
            }

            HStack(alignment: .top) {
                Text(section.text)
                    .font(.body)
                    .lineLimit(3)
                Spacer()
                Button { showRefineSheet = true } label: {
                    Image(systemName: "sparkles")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("refineSection_\(section.index)")
            }

            HStack(spacing: 8) {
                Spacer()
                actionButton
            }
        }
        .padding(.vertical, 4)
        // All navigation destinations declared once, on the outer VStack
        .navigationDestination(isPresented: $navigateToRecord) {
            TeleprompterRecordingView(section: section, project: project)
        }
        .navigationDestination(isPresented: $navigateToCaptionEditor) {
            CaptionEditorView(section: section, project: project)
        }
        .navigationDestination(isPresented: $navigateToTrim) {
            if section.recording != nil {
                VideoTrimView(section: section, project: project)
            }
        }
        .navigationDestination(isPresented: $navigateToBackground) {
            BackgroundEditorView(section: section, project: project)
        }
        .navigationDestination(isPresented: $navigateToRerecord) {
            TeleprompterRecordingView(section: section, project: project)
        }
        .navigationDestination(isPresented: $navigateToExport) {
            CaptionExportView(section: section, project: project)
        }
        .navigationDestination(isPresented: $navigateToReprocess) {
            BackgroundEditorView(section: section, project: project)
        }
        .onChange(of: importItem) { _, newItem in
            guard let newItem else { return }
            isImporting = true
            Task { await importVideo(from: newItem) }
        }
        .sheet(isPresented: $showRefineSheet) {
            SectionRefineSheet(section: section, project: project)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch section.status {
        case .unrecorded:
            HStack(spacing: 8) {
                Button { navigateToRecord = true } label: {
                    Label("Record", systemImage: "record.circle")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("recordButton_\(section.index)")

                PhotosPicker(selection: $importItem, matching: .videos) {
                    if isImporting {
                        ProgressView()
                            .tint(.primary)
                            .frame(width: 16, height: 16)
                    } else {
                        Label("Import Video", systemImage: "photo.badge.plus")
                            .font(.caption.bold())
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isImporting)
            }

        case .recorded:
            HStack {
                Button { navigateToCaptionEditor = true } label: {
                    Label("Edit Captions", systemImage: "captions.bubble")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)

                Button { navigateToTrim = true } label: {
                    Label("Trim", systemImage: "scissors")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)

                Button { navigateToBackground = true } label: {
                    Label("Set Backdrop", systemImage: "photo")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)

                Button { navigateToRerecord = true } label: {
                    Label("Re-record", systemImage: "arrow.clockwise")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
            }

        case .processed:
            HStack {
                Button { navigateToCaptionEditor = true } label: {
                    Label("Edit Captions", systemImage: "captions.bubble")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)

                Button { navigateToExport = true } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)

                Button { navigateToTrim = true } label: {
                    Label("Trim", systemImage: "scissors")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)

                Button { navigateToReprocess = true } label: {
                    Label("Re-process", systemImage: "arrow.clockwise")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
            }

        case .exported:
            Label("Exported", systemImage: "checkmark.circle.fill")
                .font(.caption.bold())
                .foregroundStyle(.green)
        }
    }

    private func importVideo(from item: PhotosPickerItem) async {
        defer {
            Task { @MainActor in
                isImporting = false
                importItem = nil
            }
        }

        guard let movie = try? await item.loadTransferable(type: MovieTransferable.self) else { return }
        let videoURL = movie.url

        let destURL = VideoFileManager.rawVideoURL(projectID: project.id, sectionID: section.id)
        try? FileManager.default.removeItem(at: destURL)
        guard (try? FileManager.default.copyItem(at: videoURL, to: destURL)) != nil else { return }

        let asset = AVAsset(url: destURL)
        let duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0

        let words = section.text
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

        var recording = Recording(sectionID: section.id, rawVideoURL: destURL)
        recording.captionTimestamps = timestamps
        recording.durationSeconds = duration

        var updatedSection = section
        updatedSection.recording = recording
        updatedSection.status = .recorded

        var updatedProject = project
        if var script = updatedProject.script,
           let idx = script.sections.firstIndex(where: { $0.id == section.id }) {
            script.sections[idx] = updatedSection
            updatedProject.script = script
        }

        await MainActor.run {
            appState.updateProject(updatedProject)
        }
    }
}

struct StatusBadge: View {
    let status: ScriptSection.SectionStatus

    var body: some View {
        Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case .unrecorded: return "Unrecorded"
        case .recorded: return "Recorded"
        case .processed: return "Processed"
        case .exported: return "Exported"
        }
    }

    private var color: Color {
        switch status {
        case .unrecorded: return .secondary
        case .recorded: return .blue
        case .processed: return .orange
        case .exported: return .green
        }
    }
}
