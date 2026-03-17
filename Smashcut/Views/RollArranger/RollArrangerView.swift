import SwiftUI

/// Timeline view for arranging clips (marks) into rolls (A-roll, B-roll, etc.).
struct RollArrangerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let project: Project
    let sectionIndex: Int

    @State private var vm: RollArrangerViewModel

    init(project: Project, sectionEdit: SectionEdit, sectionIndex: Int) {
        self.project = project
        self.sectionIndex = sectionIndex
        _vm = State(initialValue: RollArrangerViewModel(
            sectionEdit: sectionEdit,
            projectID: project.id
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Unused clips tray
            clipsTray

            Divider()

            // Roll lanes
            rollLanes

            Divider()

            // Roll controls
            controlBar
        }
        .navigationTitle("Arrange Rolls")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { save() }
    }

    // MARK: - Clips Tray (unused marks)

    private var clipsTray: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Clips")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(vm.unusedMarks.count) unused")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if vm.unusedMarks.isEmpty {
                Text("All clips assigned to rolls")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.unusedMarks) { mark in
                            ClipChip(mark: mark)
                                .draggable(mark.id.uuidString)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Roll Lanes

    private var rollLanes: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(vm.rolls) { roll in
                    RollLaneView(
                        roll: roll,
                        totalDuration: max(1, vm.totalDuration),
                        isSelected: vm.selectedRollID == roll.id,
                        onSelect: { vm.selectedRollID = roll.id },
                        onDelete: { vm.deleteRoll(roll) },
                        onRemoveLayer: { layerID in
                            vm.removeLayerFromRoll(rollID: roll.id, layerID: layerID)
                        }
                    )
                    .dropDestination(for: String.self) { items, _ in
                        guard let uuidString = items.first,
                              let markID = UUID(uuidString: uuidString) else { return false }
                        vm.addMarkToRoll(markID: markID, rollID: roll.id)
                        return true
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button {
                vm.addRoll()
            } label: {
                Label("Add Roll", systemImage: "plus.rectangle")
                    .font(.callout.bold())
            }
            .buttonStyle(.bordered)

            Spacer()

            VStack(alignment: .trailing) {
                Text("Duration: \(formatDuration(vm.totalDuration))")
                    .font(.caption.monospacedDigit())
                Text("\(vm.rolls.count) roll\(vm.rolls.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Save

    private func save() {
        var updated = project
        if var edits = updated.sectionEdits, sectionIndex < edits.count {
            edits[sectionIndex] = vm.sectionEdit
            updated.sectionEdits = edits

            // Dual-write: sync to legacy timeline
            if var timeline = updated.timeline, sectionIndex < timeline.segments.count {
                timeline.segments[sectionIndex] = vm.flattenToSegment()
                updated.timeline = timeline
            }
        }
        appState.updateProject(updated)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Clip Chip

private struct ClipChip: View {
    let mark: Mark

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "film")
                .font(.caption)
            Text(mark.label ?? "Clip")
                .font(.caption2)
                .lineLimit(1)
            Text(formatDuration(mark.duration))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.purple.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
        )
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        return s < 60 ? "\(s)s" : "\(s / 60)m\(s % 60)s"
    }
}

// MARK: - Roll Lane View

private struct RollLaneView: View {
    let roll: Roll
    let totalDuration: Double
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onRemoveLayer: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Roll header
            HStack {
                Text(roll.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(isSelected ? .blue : .primary)

                Spacer()

                Text(formatDuration(roll.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                if roll.name != "A-Roll" {
                    Button(role: .destructive) { onDelete() } label: {
                        Image(systemName: "trash")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Timeline bar
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(UIColor.systemGray5))
                        .frame(height: h)

                    // Roll position on section timeline
                    if totalDuration > 0 {
                        let startFrac = CGFloat(roll.startOffset / totalDuration)
                        let widthFrac = CGFloat(roll.duration / totalDuration)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(rollColor.opacity(0.3))
                            .frame(width: max(8, widthFrac * w), height: h)
                            .offset(x: startFrac * w)

                        // Layer blocks within the roll
                        ForEach(roll.layers) { rollLayer in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(rollColor.opacity(0.7))
                                .frame(width: max(6, widthFrac * w / max(1, CGFloat(roll.layers.count))), height: h - 8)
                                .offset(x: startFrac * w + 4)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        onRemoveLayer(rollLayer.id)
                                    } label: {
                                        Label("Remove from Roll", systemImage: "minus.circle")
                                    }
                                }
                        }
                    }
                }
            }
            .frame(height: 32)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.blue.opacity(0.06) : Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { onSelect() }
    }

    private var rollColor: Color {
        switch roll.name {
        case "A-Roll": return .blue
        case "B-Roll": return .orange
        default: return .purple
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
