import AVFoundation
import PhotosUI
import SwiftUI

/// Enhanced media bin with three-section library: Full Clips, Photos, Extracted Clips.
struct MediaBinView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let project: Project
    let sectionEdit: SectionEdit
    let sectionIndex: Int

    @State private var vm: MediaBinViewModel
    @State private var videoPickerItems: [PhotosPickerItem] = []
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var navigateToRecord = false
    @State private var navigateToMarkEditor = false
    @State private var markEditorMedia: SourceMedia?
    @State private var navigateToMarkAdjust = false
    @State private var adjustingMark: Mark?

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
            if vm.mediaBin.isEmpty {
                emptyState
            } else {
                mediaLibrary
            }

            Spacer(minLength: 0)

            actionBar
        }
        .navigationTitle("Media Bin")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { save() }
        .navigationDestination(isPresented: $navigateToRecord) {
            TeleprompterRecordingView(
                section: legacySection,
                project: project
            )
        }
        .navigationDestination(isPresented: $navigateToMarkEditor) {
            if let media = markEditorMedia {
                MarkEditorView(
                    project: project,
                    sectionEdit: vm.sectionEdit,
                    sectionIndex: sectionIndex,
                    sourceMedia: media
                )
            }
        }
        .navigationDestination(isPresented: $navigateToMarkAdjust) {
            if let mark = adjustingMark, let source = vm.sourceMedia(for: mark) {
                MarkAdjustView(
                    mark: mark,
                    sourceMedia: source,
                    onSave: { updatedIn, updatedOut in
                        vm.updateMark(id: mark.id, inSeconds: updatedIn, outSeconds: updatedOut)
                    }
                )
            }
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

    // MARK: - Three-Section Media Library

    private var mediaLibrary: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                // Full Clips section
                if !vm.fullClips.isEmpty {
                    sectionHeader("Full Clips", icon: "film.stack", count: vm.fullClips.count)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(vm.fullClips) { media in
                            FullClipItemView(
                                media: media,
                                markCount: vm.markCount(for: media)
                            )
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture {
                                markEditorMedia = media
                                navigateToMarkEditor = true
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    vm.removeMedia(media)
                                } label: {
                                    Label("Remove Video", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                // Photos section
                if !vm.photos.isEmpty {
                    sectionHeader("Photos", icon: "photo.on.rectangle", count: vm.photos.count)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 80), spacing: 6)],
                        spacing: 6
                    ) {
                        ForEach(vm.photos) { media in
                            MediaBinItemView(media: media)
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .contextMenu {
                                    Button(role: .destructive) {
                                        vm.removeMedia(media)
                                    } label: {
                                        Label("Remove Photo", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }

                // Extracted Clips (marks) section
                if !vm.extractedClips.isEmpty {
                    sectionHeader("Extracted Clips", icon: "scissors", count: vm.extractedClips.count)

                    ForEach(vm.extractedClips) { mark in
                        MarkCardView(mark: mark, sourceMedia: vm.sourceMedia(for: mark))
                            .onTapGesture {
                                adjustingMark = mark
                                navigateToMarkAdjust = true
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    vm.removeMark(mark)
                                } label: {
                                    Label("Delete Mark", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text("\(count)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(.top, 4)
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
        if var script = updated.script {
            let legacySection = SectionEditBridge.syncToLegacy(
                from: vm.sectionEdit,
                sectionID: vm.sectionEdit.id,
                projectID: project.id
            )
            if let idx = script.sections.firstIndex(where: { $0.id == vm.sectionEdit.id }) {
                var synced = legacySection
                synced.index = script.sections[idx].index
                script.sections[idx] = synced
                updated.script = script
            }
        }
        appState.updateProject(updated)
    }

    private var legacySection: ScriptSection {
        SectionEditBridge.syncToLegacy(
            from: vm.sectionEdit,
            sectionID: vm.sectionEdit.id,
            projectID: project.id
        )
    }
}

// MARK: - Full Clip Item (video with mark count badge)

private struct FullClipItemView: View {
    let media: SourceMedia
    let markCount: Int
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
                        Image(systemName: "film")
                            .foregroundStyle(.secondary)
                    )
            }

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

            // Mark count badge
            if markCount > 0 {
                VStack {
                    HStack {
                        Spacer()
                        Text("\(markCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Color.purple)
                            .clipShape(Circle())
                            .padding(4)
                    }
                    Spacer()
                }
            }
        }
        .clipped()
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        guard thumbnail == nil else { return }
        Task {
            let asset = AVAsset(url: media.url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 240, height: 240)
            if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                await MainActor.run { thumbnail = UIImage(cgImage: cgImage) }
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Mark Card View (extracted clip)

private struct MarkCardView: View {
    let mark: Mark
    let sourceMedia: SourceMedia?
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail at in-point
            ZStack {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary.opacity(0.2)
                        .overlay(
                            Image(systemName: "scissors")
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 80, height: 45)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(mark.label ?? "Clip")
                    .font(.subheadline.bold())
                HStack(spacing: 4) {
                    Text(formatTime(mark.inSeconds))
                    Text("-")
                    Text(formatTime(mark.outSeconds))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                Text(formatDuration(mark.duration))
                    .font(.caption2)
                    .foregroundStyle(.purple)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        guard thumbnail == nil, let url = sourceMedia?.url else { return }
        Task {
            let asset = AVAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 160, height: 160)
            let time = CMTime(seconds: mark.inSeconds, preferredTimescale: 600)
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                await MainActor.run { thumbnail = UIImage(cgImage: cgImage) }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ds = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", m, s, ds)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Media Bin Item (photo thumbnail, reused)

private struct MediaBinItemView: View {
    let media: SourceMedia
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.2)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .clipped()
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        guard thumbnail == nil else { return }
        if let data = try? Data(contentsOf: media.url),
           let img = UIImage(data: data) {
            thumbnail = img
        }
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
