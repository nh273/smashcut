import AVKit
import SwiftUI

/// Multi-mark editor: set multiple in/out points on a source video.
struct MarkEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let project: Project
    let sectionIndex: Int

    @State private var vm: MarkEditorViewModel

    init(project: Project, sectionEdit: SectionEdit, sectionIndex: Int, sourceMedia: SourceMedia) {
        self.project = project
        self.sectionIndex = sectionIndex
        _vm = State(initialValue: MarkEditorViewModel(
            sectionEdit: sectionEdit,
            sourceMedia: sourceMedia
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Video player
            playerView

            Divider()

            // Multi-mark timeline
            markTimeline
                .frame(height: 80)
                .padding(.horizontal)
                .padding(.top, 8)

            // Mark list
            markList

            Spacer()

            // Action bar
            actionBar
        }
        .navigationTitle("Mark Clips")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            save()
            vm.teardown()
        }
    }

    // MARK: - Player

    private var playerView: some View {
        ZStack {
            Color.black
            AVPlayerControllerRepresentable(player: vm.player)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .overlay(alignment: .center) {
            if !vm.isPlaying {
                Button { vm.togglePlayback() } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(radius: 4)
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            Text(formatTime(vm.currentTime))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white)
                .padding(6)
                .background(.black.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(8)
        }
        .onTapGesture { vm.togglePlayback() }
    }

    // MARK: - Multi-Mark Timeline

    private var markTimeline: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Seek gesture area
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(seekGesture(width: w))

                // Track
                Capsule()
                    .fill(Color(UIColor.systemGray4))
                    .frame(width: w, height: 6)
                    .position(x: w / 2, y: h / 2)

                // Existing marks as colored ranges
                ForEach(vm.marks) { mark in
                    if vm.duration > 0 {
                        let startFrac = CGFloat(mark.inSeconds / vm.duration)
                        let endFrac = CGFloat(mark.outSeconds / vm.duration)
                        let markWidth = max(4, (endFrac - startFrac) * w)
                        let centerX = startFrac * w + markWidth / 2

                        RoundedRectangle(cornerRadius: 3)
                            .fill(vm.selectedMarkID == mark.id ? Color.blue : Color.purple.opacity(0.6))
                            .frame(width: markWidth, height: 20)
                            .position(x: centerX, y: h / 2)
                            .onTapGesture { vm.seekToMark(mark) }
                    }
                }

                // Pending mark in-point indicator
                if let inPoint = vm.pendingMarkIn, vm.duration > 0 {
                    let frac = CGFloat(inPoint / vm.duration)
                    let pendingWidth = max(4, CGFloat(max(0, vm.currentTime - inPoint) / vm.duration) * w)
                    let centerX = frac * w + pendingWidth / 2

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.green.opacity(0.35))
                        .frame(width: pendingWidth, height: 20)
                        .position(x: centerX, y: h / 2)
                        .allowsHitTesting(false)

                    // In-point marker
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: 2, height: 28)
                        .position(x: frac * w, y: h / 2)
                        .allowsHitTesting(false)
                }

                // Playhead
                if vm.duration > 0 {
                    let frac = CGFloat(min(vm.currentTime, vm.duration) / vm.duration)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 3, height: h * 0.65)
                        .position(x: frac * w, y: h / 2)
                        .shadow(radius: 2)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Mark List

    private var markList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(vm.marks) { mark in
                    MarkRowView(
                        mark: mark,
                        isSelected: vm.selectedMarkID == mark.id,
                        onTap: { vm.seekToMark(mark) },
                        onDelete: { vm.deleteMark(mark) }
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            if vm.pendingMarkIn == nil {
                Button {
                    vm.markIn()
                } label: {
                    Label("Mark In", systemImage: "chevron.right.to.line")
                        .font(.callout.bold())
                }
                .buttonStyle(.bordered)
                .tint(.green)
            } else {
                Button {
                    vm.cancelPending()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .font(.callout.bold())
                }
                .buttonStyle(.bordered)
                .tint(.secondary)

                Button {
                    vm.markOut()
                } label: {
                    Label("Mark Out", systemImage: "chevron.left.to.line")
                        .font(.callout.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }

            Spacer()

            Text("\(vm.marks.count) clip\(vm.marks.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard vm.duration > 0 else { return }
                let frac = max(0, min(1, value.location.x / width))
                vm.seek(to: Double(frac) * vm.duration)
            }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00.0" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ds = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", m, s, ds)
    }

    private func save() {
        var updated = project
        if var edits = updated.sectionEdits, sectionIndex < edits.count {
            edits[sectionIndex] = vm.sectionEdit
            updated.sectionEdits = edits
        }
        appState.updateProject(updated)
    }
}

// MARK: - Mark Row

private struct MarkRowView: View {
    let mark: Mark
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "scissors")
                .foregroundStyle(isSelected ? .blue : .secondary)

            VStack(alignment: .leading) {
                Text(mark.label ?? "Clip")
                    .font(.subheadline.bold())
                Text("\(formatTime(mark.inSeconds)) → \(formatTime(mark.outSeconds))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(formatTime(mark.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.orange)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.blue.opacity(0.1) : Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { onTap() }
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ds = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", m, s, ds)
    }
}

// MARK: - AVPlayer UIKit Wrapper

private struct AVPlayerControllerRepresentable: UIViewControllerRepresentable {
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
