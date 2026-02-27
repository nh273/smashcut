import SwiftUI

struct SectionRowView: View {
    let section: ScriptSection
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Section \(section.index + 1)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                StatusBadge(status: section.status)
            }

            Text(section.text)
                .font(.body)
                .lineLimit(3)

            HStack(spacing: 8) {
                Spacer()
                actionButton
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch section.status {
        case .unrecorded:
            NavigationLink {
                TeleprompterRecordingView(section: section, project: project)
            } label: {
                Label("Record", systemImage: "record.circle")
                    .font(.caption.bold())
            }
            .buttonStyle(.borderedProminent)

        case .recorded:
            HStack {
                NavigationLink {
                    BackgroundEditorView(section: section, project: project)
                } label: {
                    Label("Background", systemImage: "photo")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)

                NavigationLink {
                    TeleprompterRecordingView(section: section, project: project)
                } label: {
                    Label("Re-record", systemImage: "arrow.clockwise")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
            }

        case .processed:
            HStack {
                NavigationLink {
                    CaptionExportView(section: section, project: project)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)

                NavigationLink {
                    BackgroundEditorView(section: section, project: project)
                } label: {
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
