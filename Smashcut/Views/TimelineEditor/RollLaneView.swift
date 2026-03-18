import SwiftUI

/// A single roll lane in the timeline editor showing layer blocks.
struct TimelineRollLaneView: View {
    let roll: Roll
    let vm: TimelineEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Roll header
            HStack(spacing: 4) {
                Text(roll.name)
                    .font(.caption2.bold())
                    .foregroundStyle(roll.name == "A-Roll" ? .blue : .orange)

                if !roll.layers.isEmpty {
                    Text("\(roll.layers.count)")
                        .font(.system(size: 8).bold())
                        .foregroundStyle(.white)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Color.secondary.opacity(0.5))
                        .clipShape(Circle())
                }

                Spacer()

                Button {
                    vm.inspectorMode = .roll(roll.id)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption2)
                }
            }
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                vm.inspectorMode = .roll(roll.id)
            }

            // Layer blocks within the roll
            GeometryReader { geo in
                let totalWidth = geo.size.width
                let rollScale: Double = vm.duration > 0 ? totalWidth / vm.duration : 1

                ZStack(alignment: .leading) {
                    // Roll background bar
                    let rollX = roll.startOffset * rollScale
                    let rollWidth = max(4, roll.duration * rollScale)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(rollBackgroundColor.opacity(0.08))
                        .frame(width: rollWidth, height: 24)
                        .offset(x: rollX)

                    // Individual layer blocks
                    ForEach(roll.layers) { rollLayer in
                        let layerX = roll.startOffset * rollScale
                        let layerDuration = (rollLayer.layer.trimEndSeconds ?? roll.duration)
                            - (rollLayer.layer.trimStartSeconds ?? 0)
                        let layerWidth = max(4, layerDuration * rollScale)

                        LayerBlock(
                            rollLayer: rollLayer,
                            isSelected: vm.inspectorMode == .layer(rollID: roll.id, layerID: rollLayer.id),
                            onTap: {
                                vm.inspectorMode = .layer(rollID: roll.id, layerID: rollLayer.id)
                            }
                        )
                        .frame(width: layerWidth, height: 24)
                        .offset(x: layerX)
                    }
                }
            }
            .frame(height: 24)
            .padding(.horizontal, 8)
        }
    }

    private var rollBackgroundColor: Color {
        roll.name == "A-Roll" ? .blue : .orange
    }
}

// MARK: - Layer Block

private struct LayerBlock: View {
    let rollLayer: RollLayer
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(layerColor.opacity(isSelected ? 0.5 : 0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isSelected ? layerColor : layerColor.opacity(0.4), lineWidth: isSelected ? 1.5 : 0.5)
                )

            HStack(spacing: 2) {
                Image(systemName: iconName)
                    .font(.system(size: 8))
                if rollLayer.layer.hasBackgroundRemoval {
                    Image(systemName: "person.crop.rectangle")
                        .font(.system(size: 7))
                        .foregroundStyle(.green)
                }
            }
            .foregroundStyle(layerColor)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var layerColor: Color {
        switch rollLayer.layer.type {
        case .video: return .blue
        case .photo: return .green
        case .text: return .yellow
        }
    }

    private var iconName: String {
        switch rollLayer.layer.type {
        case .video: return "video.fill"
        case .photo: return "photo.fill"
        case .text: return "textformat"
        }
    }
}
