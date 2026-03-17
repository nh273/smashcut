import SwiftUI

/// Row view for a SectionEdit in the section manager. Replaces SectionRowView for the new model.
struct SectionEditRowView: View {
    let sectionEdit: SectionEdit
    let sectionIndex: Int
    let project: Project

    @State private var navigateToMediaBin = false
    @State private var navigateToMarkEditor = false
    @State private var navigateToRollArranger = false
    @State private var navigateToCaptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Section \(sectionIndex + 1)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                EditStatusBadge(status: sectionEdit.status)
            }

            Text(sectionEdit.scriptText)
                .font(.body)
                .lineLimit(3)

            // Media count summary
            if !sectionEdit.mediaBin.isEmpty {
                HStack(spacing: 12) {
                    let videoCount = sectionEdit.mediaBin.filter { $0.type == .video }.count
                    let photoCount = sectionEdit.mediaBin.filter { $0.type == .photo }.count
                    if videoCount > 0 {
                        Label("\(videoCount) video\(videoCount == 1 ? "" : "s")", systemImage: "film")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if photoCount > 0 {
                        Label("\(photoCount) photo\(photoCount == 1 ? "" : "s")", systemImage: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !sectionEdit.marks.isEmpty {
                        Label("\(sectionEdit.marks.count) mark\(sectionEdit.marks.count == 1 ? "" : "s")", systemImage: "scissors")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                Spacer()
                actionButtons
            }
        }
        .padding(.vertical, 4)
        .navigationDestination(isPresented: $navigateToMediaBin) {
            MediaBinView(
                project: project,
                sectionEdit: sectionEdit,
                sectionIndex: sectionIndex
            )
        }
        .navigationDestination(isPresented: $navigateToMarkEditor) {
            if let firstVideo = sectionEdit.mediaBin.first(where: { $0.type == .video }) {
                MarkEditorView(
                    project: project,
                    sectionEdit: sectionEdit,
                    sectionIndex: sectionIndex,
                    sourceMedia: firstVideo
                )
            }
        }
        .navigationDestination(isPresented: $navigateToRollArranger) {
            RollArrangerView(
                project: project,
                sectionEdit: sectionEdit,
                sectionIndex: sectionIndex
            )
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch sectionEdit.status {
        case .empty:
            Button { navigateToMediaBin = true } label: {
                Label("Add Media", systemImage: "photo.badge.plus")
                    .font(.caption.bold())
            }
            .buttonStyle(.borderedProminent)

        case .hasMedia:
            HStack(spacing: 8) {
                Button { navigateToMediaBin = true } label: {
                    Label("Media Bin", systemImage: "photo.on.rectangle.angled")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)

                Button { navigateToMarkEditor = true } label: {
                    Label("Mark Clips", systemImage: "scissors")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
            }

        case .marked:
            HStack(spacing: 8) {
                Button { navigateToMediaBin = true } label: {
                    Label("Media", systemImage: "photo.on.rectangle.angled")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)

                Button { navigateToMarkEditor = true } label: {
                    Label("Edit Marks", systemImage: "scissors")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)

                Button { navigateToRollArranger = true } label: {
                    Label("Arrange Rolls", systemImage: "rectangle.split.3x1")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
            }

        case .arranged:
            HStack(spacing: 8) {
                Button { navigateToMediaBin = true } label: {
                    Label("Media", systemImage: "photo.on.rectangle.angled")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)

                Button { navigateToCaptions = true } label: {
                    Label("Captions", systemImage: "captions.bubble")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .disabled(true) // Phase 4
            }

        case .captioned:
            HStack(spacing: 8) {
                Button { navigateToMediaBin = true } label: {
                    Label("Media", systemImage: "photo.on.rectangle.angled")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)

                Label("Ready to Export", systemImage: "square.and.arrow.up")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }

        case .exported:
            Label("Exported", systemImage: "checkmark.circle.fill")
                .font(.caption.bold())
                .foregroundStyle(.green)
        }
    }
}
