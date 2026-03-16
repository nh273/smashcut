import AVKit
import SwiftUI

/// Full-screen draft preview that stitches all timeline segments into continuous
/// playback. Supports segment-boundary scrubbing, thumbnail jumping, and
/// instant jump-to-edit for any segment.
struct DraftPreviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let project: Project

    @State private var viewModel: DraftPreviewViewModel
    @State private var navigateToSegmentEdit = false

    init(project: Project) {
        self.project = project
        _viewModel = State(initialValue: DraftPreviewViewModel(project: project))
    }

    var body: some View {
        VStack(spacing: 0) {
            videoPlayer
            scrubberBar
            segmentThumbnailStrip
            transportControls
        }
        .background(Color.black)
        .navigationTitle("Draft Preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Export") {
                    // TODO: wire to export flow
                }
                .font(.body.bold())
            }
        }
        .onDisappear {
            viewModel.teardown()
        }
        .navigationDestination(isPresented: $navigateToSegmentEdit) {
            SegmentEditView(
                project: viewModel.project,
                segmentIndex: viewModel.editingSegmentIndex ?? viewModel.currentSegmentIndex
            )
        }
        .onChange(of: navigateToSegmentEdit) { _, isEditing in
            if !isEditing {
                viewModel.refreshAfterEdit(from: appState)
            }
        }
    }

    // MARK: - Video Player

    @ViewBuilder
    private var videoPlayer: some View {
        ZStack {
            VideoPlayer(player: viewModel.player)
                .allowsHitTesting(false)

            // Edit section overlay — visible when paused
            if !viewModel.isPlaying {
                VStack {
                    Spacer()
                    Button {
                        viewModel.editCurrentSegment()
                        navigateToSegmentEdit = true
                    } label: {
                        Label("Edit Section", systemImage: "pencil")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.togglePlayback()
        }
    }

    // MARK: - Scrubber Bar

    @ViewBuilder
    private var scrubberBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(Color(white: 0.2))
                    .frame(height: 6)
                    .cornerRadius(3)

                // Segment boundary markers
                ForEach(Array(viewModel.segmentStartTimes.enumerated()), id: \.offset) { _, startTime in
                    if startTime > 0 {
                        let x = viewModel.totalDuration > 0
                            ? startTime / viewModel.totalDuration * width
                            : 0
                        Rectangle()
                            .fill(Color.white.opacity(0.6))
                            .frame(width: 2, height: 12)
                            .offset(x: x - 1)
                    }
                }

                // Progress
                let progress = viewModel.totalDuration > 0
                    ? viewModel.currentTime / viewModel.totalDuration
                    : 0
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: max(0, progress * width), height: 6)
                    .cornerRadius(3)

                // Playhead knob
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .shadow(radius: 2)
                    .offset(x: max(0, progress * width - 7))
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard width > 0, viewModel.totalDuration > 0 else { return }
                        let fraction = max(0, min(1, value.location.x / width))
                        viewModel.seek(to: fraction * viewModel.totalDuration)
                    }
            )
        }
        .frame(height: 20)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Segment Thumbnail Strip

    @ViewBuilder
    private var segmentThumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(viewModel.timeline.segments.enumerated()), id: \.element.id) { index, segment in
                        segmentThumbnail(segment: segment, index: index)
                            .id(segment.id)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: viewModel.currentSegmentIndex) { _, newIndex in
                if newIndex < viewModel.timeline.segments.count {
                    withAnimation {
                        proxy.scrollTo(viewModel.timeline.segments[newIndex].id, anchor: .center)
                    }
                }
            }
        }
        .frame(height: 72)
        .background(Color(white: 0.1))
    }

    @ViewBuilder
    private func segmentThumbnail(segment: TimelineSegment, index: Int) -> some View {
        let isActive = index == viewModel.currentSegmentIndex
        VStack(spacing: 2) {
            ZStack {
                if let thumb = viewModel.segmentThumbnails[segment.id] {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 52, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(white: 0.25))
                        .frame(width: 52, height: 40)
                        .overlay {
                            Image(systemName: "film")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
            )

            Text("\(index + 1)")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(isActive ? .primary : .secondary)
        }
        .onTapGesture {
            viewModel.jumpToSegment(at: index)
        }
    }

    // MARK: - Transport Controls

    @ViewBuilder
    private var transportControls: some View {
        HStack(spacing: 24) {
            // Skip back 15s
            Button {
                viewModel.skipBackward()
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.title3)
            }

            // Play/pause
            Button {
                viewModel.togglePlayback()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title)
            }

            // Skip forward 15s
            Button {
                viewModel.skipForward()
            } label: {
                Image(systemName: "goforward.15")
                    .font(.title3)
            }

            Spacer()

            // Time display
            Text(formatTime(viewModel.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("/")
                .foregroundStyle(.tertiary)
            Text(formatTime(viewModel.totalDuration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(white: 0.1))
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
