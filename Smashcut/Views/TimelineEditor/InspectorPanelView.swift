import SwiftUI

/// Context-sensitive inspector panel for the timeline editor.
/// Switches content based on the current inspectorMode.
struct InspectorPanelView: View {
    let vm: TimelineEditorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch vm.inspectorMode {
                case .none:
                    noneInspector
                case .roll(let rollID):
                    if let roll = vm.sectionEdit.rolls.first(where: { $0.id == rollID }) {
                        rollInspector(roll: roll)
                    }
                case .layer(let rollID, let layerID):
                    if let rollIdx = vm.sectionEdit.rolls.firstIndex(where: { $0.id == rollID }),
                       let rollLayer = vm.sectionEdit.rolls[rollIdx].layers.first(where: { $0.id == layerID }) {
                        layerInspector(rollID: rollID, rollLayer: rollLayer)
                    }
                case .caption(let index):
                    if index < vm.chunks.count {
                        captionInspector(index: index)
                    }
                }
            }
            .padding(12)
        }
        .frame(maxHeight: 200)
        .background(Color(UIColor.secondarySystemGroupedBackground))
    }

    // MARK: - None (default) Inspector

    @ViewBuilder
    private var noneInspector: some View {
        HStack(spacing: 12) {
            Button {
                vm.addRoll()
            } label: {
                Label("Add Roll", systemImage: "plus.rectangle.on.rectangle")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)

            Toggle("Linked Captions", isOn: Binding(
                get: { vm.isLinkedMode },
                set: { vm.isLinkedMode = $0 }
            ))
            .font(.caption)
            .toggleStyle(.switch)

            Spacer()
        }

        if !vm.unusedMarks.isEmpty {
            Text("\(vm.unusedMarks.count) unused clip\(vm.unusedMarks.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Roll Inspector

    @ViewBuilder
    private func rollInspector(roll: Roll) -> some View {
        HStack {
            Image(systemName: "rectangle.split.3x1")
                .foregroundStyle(.orange)
            Text(roll.name)
                .font(.subheadline.bold())
            Spacer()
            Button(role: .destructive) {
                vm.deleteRoll(roll.id)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
        }

        // Roll timing
        HStack {
            Text("Start")
                .font(.caption)
            Slider(value: Binding(
                get: { roll.startOffset },
                set: { vm.updateRollTiming(id: roll.id, startOffset: $0, duration: roll.duration) }
            ), in: 0...max(0.1, vm.duration))
            Text(formatTime(roll.startOffset))
                .font(.caption.monospacedDigit())
                .frame(width: 40)
        }

        HStack {
            Text("Duration")
                .font(.caption)
            Slider(value: Binding(
                get: { roll.duration },
                set: { vm.updateRollTiming(id: roll.id, startOffset: roll.startOffset, duration: $0) }
            ), in: 0.1...max(0.2, vm.duration))
            Text(formatTime(roll.duration))
                .font(.caption.monospacedDigit())
                .frame(width: 40)
        }

        // Layers in this roll
        Text("Layers: \(roll.layers.count)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Layer Inspector

    @ViewBuilder
    private func layerInspector(rollID: UUID, rollLayer: RollLayer) -> some View {
        HStack {
            Image(systemName: layerIcon(rollLayer.layer.type))
                .foregroundStyle(layerColor(rollLayer.layer.type))
            Text("\(rollLayer.layer.type.rawValue.capitalized) Layer")
                .font(.subheadline.bold())
            Spacer()
            Button(role: .destructive) {
                vm.removeLayerFromRoll(rollID: rollID, layerID: rollLayer.id)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
        }

        // Volume (video only)
        if rollLayer.layer.type == .video {
            HStack {
                Image(systemName: rollLayer.layer.volume == 0 ? "speaker.slash" : "speaker.wave.2")
                    .font(.caption)
                Slider(value: Binding(
                    get: { rollLayer.layer.volume },
                    set: { vm.setLayerVolume(rollID: rollID, layerID: rollLayer.id, volume: $0) }
                ), in: 0...1)
                Text("\(Int(rollLayer.layer.volume * 100))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 36)
            }

            Toggle("BG Removal", isOn: Binding(
                get: { rollLayer.layer.hasBackgroundRemoval },
                set: { _ in vm.toggleBackgroundRemoval(rollID: rollID, layerID: rollLayer.id) }
            ))
            .font(.caption)
        }

        // Filter
        HStack {
            Text("Filter")
                .font(.caption)
            Spacer()
            Picker("Filter", selection: Binding(
                get: { rollLayer.layer.filter },
                set: { vm.setLayerFilter(rollID: rollID, layerID: rollLayer.id, filter: $0) }
            )) {
                ForEach([FilterPreset.none, .vivid, .matte, .noir, .fade], id: \.self) { preset in
                    Text(preset.rawValue.capitalized).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
        }

        // Border
        HStack {
            Text("Border")
                .font(.caption)
            Slider(value: Binding(
                get: { rollLayer.layer.borderWidth },
                set: { vm.setLayerBorderWidth(rollID: rollID, layerID: rollLayer.id, width: $0) }
            ), in: 0...10)
            Text("\(Int(rollLayer.layer.borderWidth))")
                .font(.caption.monospacedDigit())
                .frame(width: 24)
        }

        HStack {
            Text("Radius")
                .font(.caption)
            Slider(value: Binding(
                get: { rollLayer.layer.cornerRadius },
                set: { vm.setLayerCornerRadius(rollID: rollID, layerID: rollLayer.id, radius: $0) }
            ), in: 0...50)
            Text("\(Int(rollLayer.layer.cornerRadius))")
                .font(.caption.monospacedDigit())
                .frame(width: 24)
        }
    }

    // MARK: - Caption Inspector

    @ViewBuilder
    private func captionInspector(index: Int) -> some View {
        let chunk = vm.chunks[index]

        HStack {
            Image(systemName: "captions.bubble")
                .foregroundStyle(.teal)
            Text("Caption \(index + 1)")
                .font(.subheadline.bold())
            Spacer()
            Button(role: .destructive) {
                vm.deleteCaption(at: index)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
        }

        // Text editor
        TextField("Caption text", text: Binding(
            get: { chunk.text },
            set: { vm.setCaptionText(at: index, text: $0) }
        ))
        .textFieldStyle(.roundedBorder)
        .font(.caption)

        // Vertical position
        HStack {
            Text("Position")
                .font(.caption)
            Slider(value: Binding(
                get: { chunk.verticalPosition },
                set: { vm.setCaptionVerticalPosition(at: index, position: $0) }
            ), in: 0...1)
            Text("\(Int(chunk.verticalPosition * 100))%")
                .font(.caption.monospacedDigit())
                .frame(width: 36)
        }

        // Timing info
        HStack {
            Text("\(formatTime(chunk.startSeconds)) - \(formatTime(chunk.endSeconds))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                vm.splitCaption(at: index)
            } label: {
                Label("Split", systemImage: "scissors")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Helpers

    private func layerIcon(_ type: LayerType) -> String {
        switch type {
        case .video: return "video.fill"
        case .photo: return "photo.fill"
        case .text: return "textformat"
        }
    }

    private func layerColor(_ type: LayerType) -> Color {
        switch type {
        case .video: return .blue
        case .photo: return .green
        case .text: return .yellow
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
