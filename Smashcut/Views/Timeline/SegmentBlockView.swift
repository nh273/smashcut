import SwiftUI

/// A single segment block in the timeline showing thumbnail header and layer tracks.
struct SegmentBlockView: View {
    let segment: TimelineSegment
    let segmentIndex: Int
    let scale: CGFloat
    let isSelected: Bool
    let onTap: () -> Void
    let onDurationChange: (Double) -> Void
    let onLayerOffsetChange: (UUID, Double) -> Void
    let onLayerVolumeChange: (UUID, Double) -> Void
    let onReorder: (ReorderDirection) -> Void

    @State private var thumbnail: UIImage?
    @GestureState private var durationDragDelta: CGFloat = 0

    private var displayWidth: CGFloat {
        max(40, segment.duration * scale + durationDragDelta)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            thumbnailHeader

            ForEach(segment.layers, id: \.id) { layer in
                LayerTrackView(
                    layer: layer,
                    segmentDuration: segment.duration,
                    scale: scale,
                    onOffsetChange: { offset in
                        onLayerOffsetChange(layer.id, offset)
                    },
                    onVolumeChange: { volume in
                        onLayerVolumeChange(layer.id, volume)
                    }
                )
            }

            ForEach(segment.textLayers, id: \.id) { textLayer in
                TextLayerTrackView(
                    textLayer: textLayer,
                    segmentDuration: segment.duration,
                    scale: scale
                )
            }

            if segment.layers.isEmpty && segment.textLayers.isEmpty {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(UIColor.systemGray5))
                    .frame(height: 24)
                    .overlay {
                        Text("No layers")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: displayWidth)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isSelected
                        ? Color.blue.opacity(0.12)
                        : Color(UIColor.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
        .onTapGesture { onTap() }
        .contextMenu {
            Button { onReorder(.up) } label: {
                Label("Move Left", systemImage: "arrow.left")
            }
            Button { onReorder(.down) } label: {
                Label("Move Right", systemImage: "arrow.right")
            }
        }
        .overlay(alignment: .trailing) {
            durationHandle
        }
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailHeader: some View {
        ZStack(alignment: .bottomLeading) {
            if let thumb = thumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 40)
                    .clipped()
            } else {
                Color(UIColor.systemGray5)
                    .frame(height: 40)
                    .overlay {
                        Image(systemName: "film")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
            }

            Text("Seg \(segmentIndex + 1)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(Color.black.opacity(0.55))
                .cornerRadius(2)
                .padding(2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task { await loadThumbnail() }
    }

    // MARK: - Duration Handle

    @ViewBuilder
    private var durationHandle: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.orange.opacity(0.7))
            .frame(width: 6)
            .padding(.vertical, 2)
            .contentShape(Rectangle().inset(by: -8))
            .gesture(
                DragGesture()
                    .updating($durationDragDelta) { value, state, _ in
                        state = value.translation.width
                    }
                    .onEnded { value in
                        let newDuration = max(
                            0.5,
                            segment.duration + Double(value.translation.width) / scale)
                        onDurationChange(newDuration)
                    }
            )
    }

    // MARK: - Thumbnail Loading

    private func loadThumbnail() async {
        guard let videoLayer = segment.layers.first(where: { $0.type == .video }),
              let url = videoLayer.sourceURL
        else { return }
        if let data = await ThumbnailService.generateThumbnail(from: url) {
            thumbnail = UIImage(data: data)
        }
    }
}

// MARK: - Layer Track

struct LayerTrackView: View {
    let layer: Layer
    let segmentDuration: Double
    let scale: CGFloat
    let onOffsetChange: (Double) -> Void
    let onVolumeChange: (Double) -> Void

    @GestureState private var dragOffsetDelta: CGFloat = 0

    private var layerColor: Color {
        switch layer.type {
        case .video: return .blue
        case .photo: return .green
        case .text: return .yellow
        }
    }

    private var effectiveDuration: Double {
        let trimStart = layer.trimStartSeconds ?? 0
        let trimEnd = layer.trimEndSeconds ?? segmentDuration
        return max(0, trimEnd - trimStart)
    }

    private var layerWidth: CGFloat {
        max(20, effectiveDuration * scale)
    }

    private var offsetX: CGFloat {
        layer.startOffset * scale + dragOffsetDelta
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Background track
            Color(UIColor.systemGray6)
                .frame(height: 28)
                .cornerRadius(3)

            // Layer bar
            RoundedRectangle(cornerRadius: 3)
                .fill(layerColor.opacity(0.7))
                .frame(width: layerWidth, height: 28)
                .overlay(alignment: .leading) {
                    // Volume indicator bar
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            RoundedRectangle(cornerRadius: 1)
                                .fill(layerColor)
                                .frame(
                                    width: max(0, geo.size.width * layer.volume - 4),
                                    height: 4)
                                .padding(.horizontal, 2)
                                .padding(.bottom, 2)
                        }
                    }
                }
                .overlay {
                    HStack(spacing: 2) {
                        Image(systemName: layerIcon)
                            .font(.system(size: 8))
                        Text(layer.type.rawValue)
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                }
                .offset(x: max(0, offsetX))
                .gesture(
                    DragGesture()
                        .updating($dragOffsetDelta) { value, state, _ in
                            state = value.translation.width
                        }
                        .onEnded { value in
                            let delta = Double(value.translation.width) / scale
                            onOffsetChange(max(0, layer.startOffset + delta))
                        }
                )
                .contextMenu {
                    ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { vol in
                        Button {
                            onVolumeChange(vol)
                        } label: {
                            Label(
                                "Volume \(Int(vol * 100))%",
                                systemImage: vol == 0 ? "speaker.slash" : "speaker.wave.\(min(3, Int(vol * 3) + 1))")
                        }
                    }
                }
        }
        .frame(height: 28)
    }

    private var layerIcon: String {
        switch layer.type {
        case .video: return "video.fill"
        case .photo: return "photo.fill"
        case .text: return "textformat"
        }
    }
}

// MARK: - Text Layer Track

struct TextLayerTrackView: View {
    let textLayer: TextLayer
    let segmentDuration: Double
    let scale: CGFloat

    private var startX: CGFloat {
        guard segmentDuration > 0 else { return 0 }
        return textLayer.startSeconds * scale
    }

    private var barWidth: CGFloat {
        let dur = max(0, textLayer.endSeconds - textLayer.startSeconds)
        return max(10, dur * scale)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Color(UIColor.systemGray6)
                .frame(height: 20)
                .cornerRadius(3)

            RoundedRectangle(cornerRadius: 3)
                .fill(Color.yellow.opacity(0.7))
                .frame(width: barWidth, height: 20)
                .overlay {
                    Text(textLayer.text)
                        .font(.system(size: 7))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .padding(.horizontal, 2)
                }
                .offset(x: startX)
        }
        .frame(height: 20)
    }
}
