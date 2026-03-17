import AVFoundation
import PhotosUI
import SwiftUI

/// Multi-select media bin for a section. Allows importing videos/photos and recording via teleprompter.
struct MediaBinView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let project: Project
    let sectionEdit: SectionEdit
    /// Index of this section in the project's sectionEdits array.
    let sectionIndex: Int

    @State private var vm: MediaBinViewModel
    @State private var videoPickerItems: [PhotosPickerItem] = []
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showVideoPicker = false
    @State private var showPhotoPicker = false
    @State private var navigateToRecord = false

    init(project: Project, sectionEdit: SectionEdit, sectionIndex: Int) {
        self.project = project
        self.sectionEdit = sectionEdit
        self.sectionIndex = sectionIndex
        _vm = State(initialValue: MediaBinViewModel(
            sectionEdit: sectionEdit,
            projectID: project.id,
            sectionID: sectionEdit.id
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with script text
            VStack(alignment: .leading, spacing: 8) {
                Text(vm.sectionEdit.scriptText)
                    .font(.body)
                    .lineLimit(3)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                EditStatusBadge(status: vm.sectionEdit.status)
                    .padding(.horizontal)
            }
            .padding(.vertical, 12)

            Divider()

            // Media grid
            if vm.mediaBin.isEmpty {
                emptyState
            } else {
                mediaGrid
            }

            Spacer()

            // Action bar
            actionBar
        }
        .navigationTitle("Media Bin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { save() }
            }
        }
        .navigationDestination(isPresented: $navigateToRecord) {
            TeleprompterRecordingView(
                section: legacySection,
                project: project
            )
        }
        .onChange(of: videoPickerItems) { _, items in
            guard let item = items.first else { return }
            videoPickerItems = []
            Task { await vm.importVideo(from: item) }
        }
        .onChange(of: photoPickerItems) { _, items in
            guard items.count > 0 else { return }
            let toImport = items
            photoPickerItems = []
            Task { await vm.importPhotos(from: toImport) }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("No media yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Record with the teleprompter or import videos and photos")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Media Grid

    private var mediaGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 100), spacing: 8)],
                spacing: 8
            ) {
                ForEach(vm.mediaBin) { media in
                    MediaBinItemView(media: media)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .contextMenu {
                            Button(role: .destructive) {
                                vm.removeMedia(media)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            }
            .padding()
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                navigateToRecord = true
            } label: {
                Label("Record", systemImage: "record.circle")
                    .font(.callout.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            PhotosPicker(
                selection: $videoPickerItems,
                maxSelectionCount: 1,
                matching: .videos
            ) {
                Label("Import Video", systemImage: "film.stack")
                    .font(.callout.bold())
            }
            .buttonStyle(.bordered)

            PhotosPicker(
                selection: $photoPickerItems,
                maxSelectionCount: 10,
                matching: .images
            ) {
                Label("Photos", systemImage: "photo.badge.plus")
                    .font(.callout.bold())
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Save

    private func save() {
        var updated = project
        if var edits = updated.sectionEdits {
            if sectionIndex < edits.count {
                edits[sectionIndex] = vm.sectionEdit
                updated.sectionEdits = edits
            }
        }
        // Dual-write: sync back to legacy Script
        if var script = updated.script {
            let legacySection = SectionEditBridge.syncToLegacy(
                from: vm.sectionEdit,
                sectionID: vm.sectionEdit.id,
                projectID: project.id
            )
            if let idx = script.sections.firstIndex(where: { $0.id == vm.sectionEdit.id }) {
                // Preserve index
                var synced = legacySection
                synced.index = script.sections[idx].index
                script.sections[idx] = synced
                updated.script = script
            }
        }
        appState.updateProject(updated)
        dismiss()
    }

    /// Bridge: create a legacy ScriptSection for the recording view.
    private var legacySection: ScriptSection {
        SectionEditBridge.syncToLegacy(
            from: vm.sectionEdit,
            sectionID: vm.sectionEdit.id,
            projectID: project.id
        )
    }
}

// MARK: - Media Bin Item

private struct MediaBinItemView: View {
    let media: SourceMedia
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.2)
                    .overlay(
                        Image(systemName: media.type == .video ? "film" : "photo")
                            .foregroundStyle(.secondary)
                    )
            }

            if media.type == .video {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                    Text(formatDuration(media.durationSeconds))
                        .font(.caption2.monospacedDigit())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(4)
            }
        }
        .clipped()
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        guard thumbnail == nil else { return }
        if media.type == .video {
            Task {
                let asset = AVAsset(url: media.url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 240, height: 240)
                if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                    await MainActor.run { thumbnail = UIImage(cgImage: cgImage) }
                }
            }
        } else {
            // Photo: load from file URL
            if let data = try? Data(contentsOf: media.url),
               let img = UIImage(data: data) {
                thumbnail = img
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Edit Status Badge

struct EditStatusBadge: View {
    let status: EditStatus

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
        case .empty: return "Empty"
        case .hasMedia: return "Has Media"
        case .marked: return "Marked"
        case .arranged: return "Arranged"
        case .captioned: return "Captioned"
        case .exported: return "Exported"
        }
    }

    private var color: Color {
        switch status {
        case .empty: return .secondary
        case .hasMedia: return .blue
        case .marked: return .purple
        case .arranged: return .orange
        case .captioned: return .teal
        case .exported: return .green
        }
    }
}
