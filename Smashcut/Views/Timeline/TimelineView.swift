import AVKit
import SwiftUI

struct ProjectTimelineView: View {
    @Environment(AppState.self) private var appState
    let project: Project

    @State private var viewModel: TimelineViewModel

    init(project: Project) {
        self.project = project
        self._viewModel = State(initialValue: TimelineViewModel(project: project))
    }

    var body: some View {
        VStack(spacing: 0) {
            videoPreview
            transportControls
            Divider()
            timelineArea
        }
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    viewModel.saveChanges(to: appState)
                }
            }
        }
        .onDisappear {
            viewModel.teardown()
        }
    }

    // MARK: - Video Preview

    @ViewBuilder
    private var videoPreview: some View {
        VideoPlayer(player: viewModel.player)
            .frame(height: 220)
            .background(Color.black)
            .allowsHitTesting(false)
    }

    // MARK: - Transport Controls

    @ViewBuilder
    private var transportControls: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.togglePlayback()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }

            Text(formatTime(viewModel.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Text("/")
                .foregroundStyle(.tertiary)

            Text(formatTime(viewModel.totalDuration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                viewModel.scale = max(20, viewModel.scale * 0.75)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }

            Button {
                viewModel.scale = min(500, viewModel.scale * 1.33)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Timeline Area

    @ViewBuilder
    private var timelineArea: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    // Ruler + seek tap area
                    TimelineRulerView(
                        totalDuration: viewModel.totalDuration,
                        scale: viewModel.scale,
                        onSeek: { viewModel.seek(to: $0) }
                    )
                    .frame(height: 20)

                    // Segment blocks
                    HStack(spacing: 2) {
                        ForEach(
                            Array(viewModel.timeline.segments.enumerated()),
                            id: \.element.id
                        ) { index, segment in
                            SegmentBlockView(
                                segment: segment,
                                segmentIndex: index,
                                scale: viewModel.scale,
                                isSelected: viewModel.selectedSegmentID == segment.id,
                                onTap: { viewModel.selectSegment(at: index) },
                                onDurationChange: { newDur in
                                    viewModel.updateSegmentDuration(
                                        segmentID: segment.id, duration: newDur)
                                },
                                onLayerOffsetChange: { layerID, offset in
                                    viewModel.updateLayerOffset(
                                        segmentID: segment.id, layerID: layerID,
                                        offset: offset)
                                },
                                onLayerVolumeChange: { layerID, volume in
                                    viewModel.updateLayerVolume(
                                        segmentID: segment.id, layerID: layerID,
                                        volume: volume)
                                },
                                onReorder: { direction in
                                    reorderSegment(at: index, direction: direction)
                                }
                            )
                        }
                    }
                    .padding(.top, 24)

                    // Playhead
                    if viewModel.totalDuration > 0 {
                        let playheadX = viewModel.currentTime * viewModel.scale
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 2)
                            .offset(x: playheadX)
                            .allowsHitTesting(false)
                    }
                }
                .frame(
                    minWidth: max(
                        geo.size.width,
                        viewModel.totalDuration * viewModel.scale + 40)
                )
            }
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        viewModel.scale = max(20, min(500, viewModel.scale * value.magnification))
                    }
            )
        }
        .frame(maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Helpers

    private func reorderSegment(at index: Int, direction: ReorderDirection) {
        switch direction {
        case .up where index > 0:
            viewModel.timeline.segments.swapAt(index, index - 1)
        case .down where index < viewModel.timeline.segments.count - 1:
            viewModel.timeline.segments.swapAt(index, index + 1)
        default:
            break
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

enum ReorderDirection {
    case up, down
}

// MARK: - Timeline Ruler

private struct TimelineRulerView: View {
    let totalDuration: Double
    let scale: CGFloat
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                let tickInterval = rulerTickInterval(scale: scale)
                var t: Double = 0
                while t <= totalDuration {
                    let x = t * scale
                    let isMajor = t.truncatingRemainder(dividingBy: tickInterval * 5) < 0.001
                    let tickH: CGFloat = isMajor ? 12 : 6
                    context.stroke(
                        Path { p in
                            p.move(to: CGPoint(x: x, y: size.height - tickH))
                            p.addLine(to: CGPoint(x: x, y: size.height))
                        },
                        with: .color(.secondary.opacity(0.5)),
                        lineWidth: 1
                    )
                    if isMajor {
                        let label = rulerLabel(t)
                        context.draw(
                            Text(label)
                                .font(.system(size: 8))
                                .foregroundColor(.secondary),
                            at: CGPoint(x: x, y: 4),
                            anchor: .top
                        )
                    }
                    t += tickInterval
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard scale > 0 else { return }
                        let seconds = max(0, min(totalDuration, Double(value.location.x) / scale))
                        onSeek(seconds)
                    }
            )
        }
    }

    private func rulerTickInterval(scale: CGFloat) -> Double {
        if scale > 200 { return 0.5 }
        if scale > 80 { return 1 }
        if scale > 30 { return 5 }
        return 10
    }

    private func rulerLabel(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
