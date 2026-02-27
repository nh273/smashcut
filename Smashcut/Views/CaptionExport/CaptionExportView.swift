import SwiftUI

struct CaptionExportView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let section: ScriptSection
    let project: Project

    @State private var isBurningIn = false
    @State private var burnProgress: Double = 0
    @State private var burnError: String?
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false

    private var captions: [CaptionTimestamp] {
        section.recording?.captionTimestamps ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sectionInfo

                captionPreview

                exportActions
            }
            .padding()
        }
        .navigationTitle("Caption Export")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
        .alert("Export Error", isPresented: .constant(burnError != nil)) {
            Button("OK") { burnError = nil }
        } message: {
            Text(burnError ?? "")
        }
    }

    private var sectionInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Section \(section.index + 1)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(section.text)
                .font(.body)
                .lineLimit(4)
            if let duration = section.recording?.durationSeconds {
                Text("\(String(format: "%.1f", duration))s · \(captions.count) word timestamps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var captionPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SRT Preview")
                .font(.headline)
            ScrollView {
                Text(srtPreview)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(height: 200)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var srtPreview: String {
        let srt = TimingUtilities.exportSRT(captions)
        return srt.isEmpty ? "No caption timestamps recorded." : srt
    }

    private var exportActions: some View {
        VStack(spacing: 12) {
            Button {
                exportSRT()
            } label: {
                Label("Export SRT File", systemImage: "doc.text")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(captions.isEmpty)

            if let videoURL = section.recording?.compositeVideoURL ?? section.recording?.rawVideoURL {
                Button {
                    Task { await burnCaptions(videoURL: videoURL) }
                } label: {
                    if isBurningIn {
                        HStack {
                            ProgressView()
                            Text("Burning captions… \(Int(burnProgress * 100))%")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Label("Export with Burned Captions", systemImage: "captions.bubble")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBurningIn || captions.isEmpty)
            }
        }
    }

    private func exportSRT() {
        let srt = TimingUtilities.exportSRT(captions)
        let url = VideoFileManager.srtURL(projectID: project.id, sectionID: section.id)
        try? srt.write(to: url, atomically: true, encoding: .utf8)
        shareItems = [url]
        showShareSheet = true

        // Mark exported
        markExported()
    }

    private func burnCaptions(videoURL: URL) async {
        isBurningIn = true
        burnError = nil

        let outputURL = VideoFileManager.exportedVideoURL(projectID: project.id, sectionID: section.id)

        do {
            try await CompositionService.shared.burnCaptions(
                inputURL: videoURL,
                captions: captions,
                outputURL: outputURL
            )
            await MainActor.run {
                isBurningIn = false
                shareItems = [outputURL]
                showShareSheet = true
                markExported()
            }
        } catch {
            await MainActor.run {
                isBurningIn = false
                burnError = error.localizedDescription
            }
        }
    }

    private func markExported() {
        var updated = project
        if var script = updated.script,
           let idx = script.sections.firstIndex(where: { $0.id == section.id }) {
            script.sections[idx].status = .exported
            updated.script = script
            appState.updateProject(updated)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
