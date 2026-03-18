import AVKit
import SwiftUI

/// Unified timeline editor merging roll arrangement, caption editing, and spatial composition.
struct TimelineEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let project: Project
    let sectionEdit: SectionEdit
    let sectionIndex: Int

    @State private var vm: TimelineEditorViewModel

    init(project: Project, sectionEdit: SectionEdit, sectionIndex: Int) {
        self.project = project
        self.sectionEdit = sectionEdit
        self.sectionIndex = sectionIndex
        _vm = State(initialValue: TimelineEditorViewModel(
            sectionEdit: sectionEdit,
            projectID: project.id
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            compositePreview
            transportControls
            Divider()
            timelineLanes
            Divider()
            InspectorPanelView(vm: vm)
        }
        .navigationTitle("Timeline Editor")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    vm.showGrid.toggle()
                } label: {
                    Image(systemName: vm.showGrid ? "grid" : "grid.circle")
                        .foregroundStyle(vm.showGrid ? .blue : .secondary)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .onDisappear { vm.teardown() }
    }

    // MARK: - Composite Preview

    @ViewBuilder
    private var compositePreview: some View {
        GeometryReader { geo in
            ZStack {
                VideoPlayer(player: vm.player)
                    .allowsHitTesting(false)

                if vm.showGrid {
                    thirdsGrid
                        .allowsHitTesting(false)
                }

                // Selection overlay for spatial editing
                if case .layer(let rollID, let layerID) = vm.inspectorMode,
                   let rollIdx = vm.sectionEdit.rolls.firstIndex(where: { $0.id == rollID }),
                   let layer = vm.sectionEdit.rolls[rollIdx].layers.first(where: { $0.id == layerID }) {
                    SelectionOverlay(
                        position: layer.layer.position,
                        canvasSize: geo.size,
                        onPositionChange: { vm.updateLayerPosition(rollID: rollID, layerID: layerID, position: $0) }
                    )
                }
            }
        }
        .frame(height: 240)
        .background(Color.black)
        .onTapGesture { vm.inspectorMode = .none }
    }

    // MARK: - Transport Controls

    @ViewBuilder
    private var transportControls: some View {
        HStack(spacing: 12) {
            Button { vm.togglePlayback() } label: {
                Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }

            Text(formatTime(vm.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            scrubBar
                .frame(maxWidth: .infinity)

            Text(formatTime(vm.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(UIColor.systemBackground))
    }

    @ViewBuilder
    private var scrubBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(UIColor.systemGray4))
                    .frame(height: 4)

                if vm.duration > 0 {
                    let frac = vm.currentTime / vm.duration
                    Capsule()
                        .fill(Color.blue)
                        .frame(width: max(0, geo.size.width * frac), height: 4)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard vm.duration > 0 else { return }
                        let frac = max(0, min(1, value.location.x / geo.size.width))
                        vm.seek(to: frac * vm.duration)
                    }
            )
        }
        .frame(height: 28)
    }

    // MARK: - Timeline Lanes

    @ViewBuilder
    private var timelineLanes: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 4) {
                // Caption lane (always top)
                if !vm.chunks.isEmpty {
                    CaptionLaneView(vm: vm)
                }

                // Roll lanes
                ForEach(vm.sectionEdit.rolls) { roll in
                    TimelineRollLaneView(roll: roll, vm: vm)
                }

                // Unused clips tray
                if !vm.unusedMarks.isEmpty {
                    unusedClipsTray
                }
            }
            .padding(.vertical, 8)
            .frame(minWidth: max(UIScreen.main.bounds.width, vm.duration * 80))
        }
        .frame(height: 160)
        .background(Color(UIColor.systemGroupedBackground))
    }

    @ViewBuilder
    private var unusedClipsTray: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Unused Clips")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(vm.unusedMarks) { mark in
                        UnusedMarkChip(mark: mark)
                            .onTapGesture {
                                // Add to first available roll (or A-Roll)
                                if let firstRoll = vm.sectionEdit.rolls.first {
                                    vm.addMarkToRoll(markID: mark.id, rollID: firstRoll.id)
                                }
                            }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Thirds Grid

    @ViewBuilder
    private var thirdsGrid: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Canvas { context, _ in
                let color = Color.white.opacity(0.3)
                for i in 1...2 {
                    let x = w * CGFloat(i) / 3
                    context.stroke(
                        Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h)) },
                        with: .color(color), lineWidth: 0.5
                    )
                    let y = h * CGFloat(i) / 3
                    context.stroke(
                        Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y)) },
                        with: .color(color), lineWidth: 0.5
                    )
                }
            }
        }
    }

    // MARK: - Selection Overlay (reused from SegmentEditView)

    private struct SelectionOverlay: View {
        let position: NormalizedRect
        let canvasSize: CGSize
        let onPositionChange: (NormalizedRect) -> Void

        @GestureState private var dragOffset: CGSize = .zero

        private var frame: CGRect {
            CGRect(
                x: position.x * canvasSize.width + dragOffset.width,
                y: position.y * canvasSize.height + dragOffset.height,
                width: position.width * canvasSize.width,
                height: position.height * canvasSize.height
            )
        }

        var body: some View {
            Rectangle()
                .stroke(Color.blue, lineWidth: 2)
                .frame(width: frame.width, height: frame.height)
                .overlay(alignment: .topLeading) { handle }
                .overlay(alignment: .topTrailing) { handle }
                .overlay(alignment: .bottomLeading) { handle }
                .overlay(alignment: .bottomTrailing) { handle }
                .position(x: frame.midX, y: frame.midY)
                .gesture(
                    DragGesture()
                        .updating($dragOffset) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            guard canvasSize.width > 0, canvasSize.height > 0 else { return }
                            let dx = value.translation.width / canvasSize.width
                            let dy = value.translation.height / canvasSize.height
                            onPositionChange(NormalizedRect(
                                x: max(0, min(1 - position.width, position.x + dx)),
                                y: max(0, min(1 - position.height, position.y + dy)),
                                width: position.width,
                                height: position.height
                            ))
                        }
                )
        }

        private var handle: some View {
            Circle()
                .fill(Color.blue)
                .frame(width: 10, height: 10)
        }
    }

    // MARK: - Helpers

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
        dismiss()
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Unused Mark Chip

private struct UnusedMarkChip: View {
    let mark: Mark

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "scissors")
                .font(.caption2)
            Text(mark.label ?? "Clip")
                .font(.caption2)
            Text(formatDuration(mark.duration))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.purple.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
