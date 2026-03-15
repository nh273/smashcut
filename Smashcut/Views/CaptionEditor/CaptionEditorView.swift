import AVFoundation
import AVKit
import SwiftUI

struct CaptionEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let section: ScriptSection
    let project: Project

    @State private var viewModel: CaptionEditorViewModel
    @State private var player: AVPlayer?
    @State private var selectedChunkIndex: Int?

    init(section: ScriptSection, project: Project) {
        self.section = section
        self.project = project
        let recording = section.recording ?? Recording(
            sectionID: section.id,
            rawVideoURL: URL(fileURLWithPath: "")
        )
        _viewModel = State(wrappedValue: CaptionEditorViewModel(recording: recording))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 220)
                    .background(Color.black)
            }

            if viewModel.chunks.isEmpty {
                ContentUnavailableView {
                    Label("No Captions", systemImage: "captions.bubble")
                } description: {
                    Text("Record a section to generate caption timestamps.")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(viewModel.chunks.enumerated()), id: \.element.id) { index, chunk in
                            CaptionChunkRow(
                                chunk: chunk,
                                index: index,
                                totalDuration: viewModel.totalDuration,
                                isSelected: selectedChunkIndex == index,
                                videoURL: section.recording?.rawVideoURL,
                                onTap: {
                                    selectedChunkIndex = index
                                    seekPlayer(to: chunk.startSeconds)
                                },
                                onStartChanged: { newStart in
                                    viewModel.adjustStart(at: index, to: newStart)
                                },
                                onEndChanged: { newEnd in
                                    viewModel.adjustEnd(at: index, to: newEnd)
                                },
                                onVerticalPositionChanged: { newPos in
                                    viewModel.setVerticalPosition(at: index, to: newPos)
                                },
                                onApplyPositionToAll: {
                                    viewModel.applyVerticalPositionToAll(from: index)
                                },
                                onDelete: {
                                    viewModel.deleteChunk(at: index)
                                    if selectedChunkIndex == index { selectedChunkIndex = nil }
                                },
                                onAddAfter: {
                                    viewModel.addChunkAfter(index: index)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Edit Captions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .onAppear {
            if let url = section.recording?.rawVideoURL {
                player = AVPlayer(url: url)
            }
        }
    }

    private func seekPlayer(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func save() {
        var updated = project
        if var script = updated.script,
           let sIdx = script.sections.firstIndex(where: { $0.id == section.id }),
           var recording = script.sections[sIdx].recording {
            recording.captionTimestamps = viewModel.toCaptionTimestamps()
            script.sections[sIdx].recording = recording
            updated.script = script
            appState.updateProject(updated)
        }
        dismiss()
    }
}

// MARK: - Caption Chunk Row

struct CaptionChunkRow: View {
    let chunk: EditableCaptionChunk
    let index: Int
    let totalDuration: Double
    let isSelected: Bool
    let videoURL: URL?
    let onTap: () -> Void
    let onStartChanged: (Double) -> Void
    let onEndChanged: (Double) -> Void
    let onVerticalPositionChanged: (Double) -> Void
    let onApplyPositionToAll: () -> Void
    let onDelete: () -> Void
    let onAddAfter: () -> Void

    @State private var thumbnail: UIImage?

    private let thumbnailHeight: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail with caption overlay at vertical position
            thumbnailView
                .onTapGesture(perform: onTap)

            // Vertical position slider
            if isSelected {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Position")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(chunk.verticalPosition * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { chunk.verticalPosition },
                                set: { onVerticalPositionChanged($0) }
                            ),
                            in: 0.05...0.95
                        )
                        Image(systemName: "arrow.down")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        onApplyPositionToAll()
                    } label: {
                        Label("Apply to All", systemImage: "rectangle.stack")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 4)
            }

            // Timing labels
            HStack {
                Text(formatTime(chunk.startSeconds))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("→ \(formatTime(chunk.endSeconds))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Timing scrubber
            TimingScrubber(
                startSeconds: chunk.startSeconds,
                endSeconds: chunk.endSeconds,
                totalDuration: totalDuration,
                onStartChanged: onStartChanged,
                onEndChanged: onEndChanged
            )

            // Action buttons
            HStack {
                Button(action: onAddAfter) {
                    Label("Add after", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color(.systemGray4), lineWidth: isSelected ? 2 : 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        .task(id: chunk.id) {
            await loadThumbnail()
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: thumbnailHeight)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(width: width, height: thumbnailHeight)
                        .overlay(
                            ProgressView()
                        )
                }

                // Caption text positioned at verticalPosition
                Text(chunk.text)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .position(
                        x: width / 2,
                        y: thumbnailHeight * CGFloat(chunk.verticalPosition)
                    )
            }
        }
        .frame(height: thumbnailHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    private func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds)
        let tenths = Int((seconds - Double(s)) * 10)
        return String(format: "%d.%ds", s, tenths)
    }

    private func loadThumbnail() async {
        guard let url = videoURL else { return }
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 180)

        let time = CMTime(seconds: chunk.startSeconds, preferredTimescale: 600)
        guard let cgImage = try? await generator.image(at: time).image else { return }
        await MainActor.run {
            thumbnail = UIImage(cgImage: cgImage)
        }
    }
}

// MARK: - Timing Scrubber

struct TimingScrubber: View {
    let startSeconds: Double
    let endSeconds: Double
    let totalDuration: Double
    let onStartChanged: (Double) -> Void
    let onEndChanged: (Double) -> Void

    private let handleWidth: CGFloat = 18
    private let barHeight: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let startX = CGFloat(startSeconds / totalDuration) * width
            let endX = CGFloat(endSeconds / totalDuration) * width

            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(Color(.systemGray5))
                    .frame(height: 6)

                // Active range highlight
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: max(0, endX - startX), height: 6)
                    .offset(x: startX)

                // Start handle
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor)
                    .frame(width: handleWidth, height: barHeight)
                    .overlay(
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .offset(x: startX - handleWidth / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("scrubber"))
                            .onChanged { value in
                                let x = min(max(value.location.x, 0), width)
                                onStartChanged(Double(x / width) * totalDuration)
                            }
                    )

                // End handle
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor)
                    .frame(width: handleWidth, height: barHeight)
                    .overlay(
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .offset(x: endX - handleWidth / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("scrubber"))
                            .onChanged { value in
                                let x = min(max(value.location.x, 0), width)
                                onEndChanged(Double(x / width) * totalDuration)
                            }
                    )
            }
            .frame(height: barHeight)
            .coordinateSpace(name: "scrubber")
        }
        .frame(height: barHeight)
    }
}
