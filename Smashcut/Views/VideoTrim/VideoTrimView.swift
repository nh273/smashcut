import AVKit
import SwiftUI

/// Video preview with trim controls — mark entrance and exit points to crop a recording.
struct VideoTrimView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let section: ScriptSection
    let project: Project

    @State private var vm: VideoTrimViewModel

    init(section: ScriptSection, project: Project) {
        self.section = section
        self.project = project
        _vm = State(initialValue: VideoTrimViewModel(recording: section.recording!))
    }

    var body: some View {
        VStack(spacing: 0) {
            playerView

            controlsPanel
                .background(Color(.systemBackground))
        }
        .navigationTitle("Trim Video")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { vm.teardown() }
    }

    // MARK: - Player

    private var playerView: some View {
        AVPlayerControllerView(player: vm.player)
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(Color.black)
            .overlay(alignment: .center) {
                if !vm.isPlaying {
                    Button { vm.togglePlayback() } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(radius: 4)
                    }
                }
            }
            .onTapGesture { vm.togglePlayback() }
    }

    // MARK: - Controls

    private var controlsPanel: some View {
        VStack(spacing: 16) {
            timeDisplay

            TrimTimelineView(
                duration: vm.duration,
                currentTime: vm.currentTime,
                trimStart: vm.trimStart,
                trimEnd: vm.trimEnd,
                onSeek: { vm.seek(to: $0) },
                onTrimStartChange: { vm.trimStart = $0 },
                onTrimEndChange: { vm.trimEnd = $0 }
            )
            .frame(height: 56)
            .padding(.horizontal)

            markButtons

            actionRow
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var timeDisplay: some View {
        HStack {
            Label(formatTime(vm.currentTime), systemImage: "timer")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            if let start = vm.trimStart, let end = vm.trimEnd, end > start {
                Label(formatTime(end - start), systemImage: "scissors")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.orange)
            } else if vm.trimStart != nil || vm.trimEnd != nil {
                Text("Set both entrance and exit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private var markButtons: some View {
        HStack(spacing: 12) {
            Button {
                vm.markEntrance()
            } label: {
                Label("Mark Entrance", systemImage: "chevron.right.to.line")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.green)

            Button {
                vm.markExit()
            } label: {
                Label("Mark Exit", systemImage: "chevron.left.to.line")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(.horizontal)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            if vm.trimStart != nil || vm.trimEnd != nil {
                Button("Clear", role: .destructive) {
                    vm.clearTrim()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button("Save Trim") {
                saveAndDismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00.0" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ds = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", m, s, ds)
    }

    private func saveAndDismiss() {
        var updated = project
        guard var script = updated.script,
              let idx = script.sections.firstIndex(where: { $0.id == section.id }),
              var recording = script.sections[idx].recording else {
            dismiss()
            return
        }
        recording.trimStartSeconds = vm.trimStart
        recording.trimEndSeconds = vm.trimEnd
        script.sections[idx].recording = recording
        updated.script = script
        appState.updateProject(updated)
        dismiss()
    }
}

// MARK: - AVPlayerControllerView

/// Wraps AVPlayerViewController with native controls hidden so we can use our own.
private struct AVPlayerControllerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = false
        vc.videoGravity = .resizeAspect
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        vc.player = player
    }
}
