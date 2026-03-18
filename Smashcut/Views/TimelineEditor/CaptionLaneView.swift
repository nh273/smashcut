import SwiftUI

/// Horizontal lane showing caption chunks as draggable bars in the timeline editor.
struct CaptionLaneView: View {
    let vm: TimelineEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Captions")
                .font(.caption2.bold())
                .foregroundStyle(.teal)
                .padding(.horizontal, 8)

            GeometryReader { geo in
                let totalWidth = geo.size.width
                let scale: Double = vm.duration > 0 ? totalWidth / vm.duration : 1

                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.teal.opacity(0.05))
                        .frame(height: 28)

                    // Caption chunk bars
                    ForEach(Array(vm.chunks.enumerated()), id: \.element.id) { index, chunk in
                        let x = chunk.startSeconds * scale
                        let width = max(4, (chunk.endSeconds - chunk.startSeconds) * scale)

                        CaptionChunkBar(
                            chunk: chunk,
                            index: index,
                            isSelected: vm.inspectorMode == .caption(index),
                            onTap: {
                                vm.inspectorMode = .caption(index)
                            },
                            onDragLeftEdge: { delta in
                                let timeDelta = delta / scale
                                vm.adjustCaptionStart(at: index, to: chunk.startSeconds + timeDelta)
                            },
                            onDragRightEdge: { delta in
                                let timeDelta = delta / scale
                                vm.adjustCaptionEnd(at: index, to: chunk.endSeconds + timeDelta)
                            }
                        )
                        .frame(width: width, height: 28)
                        .offset(x: x)
                    }
                }
            }
            .frame(height: 28)
            .padding(.horizontal, 8)
        }
    }
}

// MARK: - Caption Chunk Bar

private struct CaptionChunkBar: View {
    let chunk: EditableCaptionChunk
    let index: Int
    let isSelected: Bool
    let onTap: () -> Void
    let onDragLeftEdge: (Double) -> Void
    let onDragRightEdge: (Double) -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(isSelected ? Color.teal.opacity(0.4) : Color.teal.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isSelected ? Color.teal : Color.teal.opacity(0.3), lineWidth: isSelected ? 1.5 : 0.5)
                )

            Text(chunk.text)
                .font(.system(size: 8))
                .lineLimit(1)
                .padding(.horizontal, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .overlay(alignment: .leading) {
            edgeHandle(isLeft: true)
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            onDragLeftEdge(value.translation.width)
                        }
                )
        }
        .overlay(alignment: .trailing) {
            edgeHandle(isLeft: false)
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            onDragRightEdge(value.translation.width)
                        }
                )
        }
    }

    @ViewBuilder
    private func edgeHandle(isLeft: Bool) -> some View {
        Rectangle()
            .fill(Color.teal.opacity(0.01))
            .frame(width: 8)
            .contentShape(Rectangle())
    }
}
