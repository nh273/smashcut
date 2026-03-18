import AVKit
import SwiftUI

/// Lightweight view for adjusting a single mark's in/out handles on a source video.
struct MarkAdjustView: View {
    let mark: Mark
    let sourceMedia: SourceMedia
    let onSave: (Double, Double) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var player = AVPlayer()
    @State private var currentTime: Double = 0
    @State private var trimStart: Double
    @State private var trimEnd: Double
    @State private var isPlaying = false
    private var timeObserver: Any?

    init(mark: Mark, sourceMedia: SourceMedia, onSave: @escaping (Double, Double) -> Void) {
        self.mark = mark
        self.sourceMedia = sourceMedia
        self.onSave = onSave
        _trimStart = State(initialValue: mark.inSeconds)
        _trimEnd = State(initialValue: mark.outSeconds)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Video preview
            VideoPlayer(player: player)
                .frame(maxHeight: 300)
                .background(Color.black)
                .allowsHitTesting(false)

            // Transport
            HStack(spacing: 12) {
                Button {
                    if isPlaying {
                        player.pause()
                    } else {
                        player.play()
                    }
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }

                Text(formatTime(currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Duration: \(formatTime(trimEnd - trimStart))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.purple)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Trim timeline
            VStack(spacing: 8) {
                Text("Adjust In/Out Points")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                TrimTimelineView(
                    duration: sourceMedia.durationSeconds,
                    currentTime: currentTime,
                    trimStart: trimStart,
                    trimEnd: trimEnd,
                    onSeek: { seconds in
                        seek(to: seconds)
                    },
                    onTrimStartChange: { trimStart = max(0, $0) },
                    onTrimEndChange: { trimEnd = min(sourceMedia.durationSeconds, $0) }
                )
                .frame(height: 56)
                .padding(.horizontal)

                HStack {
                    Text("In: \(formatTime(trimStart))")
                        .font(.caption.monospacedDigit())
                    Spacer()
                    Text("Out: \(formatTime(trimEnd))")
                        .font(.caption.monospacedDigit())
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 12)

            Spacer()
        }
        .navigationTitle("Adjust Clip")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let item = AVPlayerItem(url: sourceMedia.url)
            player.replaceCurrentItem(with: item)
            seek(to: trimStart)
            setupTimeObserver()
        }
        .onDisappear {
            player.pause()
            onSave(trimStart, trimEnd)
        }
    }

    private func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, sourceMedia.durationSeconds))
        currentTime = clamped
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.033, preferredTimescale: 600)
        player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let t = max(0, time.seconds)
            currentTime = t
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ds = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", m, s, ds)
    }
}
