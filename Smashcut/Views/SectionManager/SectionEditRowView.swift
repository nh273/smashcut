import SwiftUI

/// Row view for a SectionEdit in the section manager. Simplified to two entry points:
/// Media (enhanced MediaBin) and Edit Timeline (unified TimelineEditor).
struct SectionEditRowView: View {
    let sectionEdit: SectionEdit
    let sectionIndex: Int
    let project: Project

    @State private var navigateToMediaBin = false
    @State private var navigateToTimelineEditor = false

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
                Button("Media") { navigateToMediaBin = true }
                    .buttonStyle(.bordered)
                Button("Edit Timeline") { navigateToTimelineEditor = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(sectionEdit.mediaBin.isEmpty)
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
        .navigationDestination(isPresented: $navigateToTimelineEditor) {
            TimelineEditorView(
                project: project,
                sectionEdit: sectionEdit,
                sectionIndex: sectionIndex
            )
        }
    }
}
