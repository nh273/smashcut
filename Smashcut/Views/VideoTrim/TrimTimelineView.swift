import SwiftUI

/// Interactive timeline bar showing trim in/out handles and playhead.
struct TrimTimelineView: View {
    let duration: Double
    let currentTime: Double
    let trimStart: Double?
    let trimEnd: Double?
    let onSeek: (Double) -> Void
    let onTrimStartChange: (Double) -> Void
    let onTrimEndChange: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let midY = h / 2

            ZStack {
                // Full-area transparent tap/drag for seeking (lowest layer)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(seekGesture(width: w))

                // Track
                Capsule()
                    .fill(Color(UIColor.systemGray4))
                    .frame(width: w, height: 6)
                    .position(x: w / 2, y: midY)

                // Trim range highlight
                if let start = trimStart, let end = trimEnd, duration > 0, end > start {
                    let startFrac = CGFloat(start / duration)
                    let endFrac = CGFloat(end / duration)
                    let hlWidth = (endFrac - startFrac) * w
                    let hlCenterX = startFrac * w + hlWidth / 2
                    Capsule()
                        .fill(Color.orange.opacity(0.45))
                        .frame(width: hlWidth, height: 6)
                        .position(x: hlCenterX, y: midY)
                        .allowsHitTesting(false)
                }

                // Playhead
                if duration > 0 {
                    let frac = CGFloat(min(currentTime, duration) / duration)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 3, height: h * 0.65)
                        .position(x: frac * w, y: midY)
                        .shadow(radius: 2)
                        .allowsHitTesting(false)
                }

                // Entrance handle
                if let start = trimStart, duration > 0 {
                    TrimHandleView(
                        isEntrance: true,
                        fraction: CGFloat(start / duration),
                        timelineWidth: w,
                        timelineHeight: h,
                        onFractionChange: { onTrimStartChange(Double($0) * duration) }
                    )
                }

                // Exit handle
                if let end = trimEnd, duration > 0 {
                    TrimHandleView(
                        isEntrance: false,
                        fraction: CGFloat(end / duration),
                        timelineWidth: w,
                        timelineHeight: h,
                        onFractionChange: { onTrimEndChange(Double($0) * duration) }
                    )
                }
            }
        }
    }

    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard duration > 0 else { return }
                let frac = max(0, min(1, value.location.x / width))
                onSeek(Double(frac) * duration)
            }
    }
}

/// A draggable handle marking the entrance or exit point on the trim timeline.
private struct TrimHandleView: View {
    let isEntrance: Bool
    let fraction: CGFloat
    let timelineWidth: CGFloat
    let timelineHeight: CGFloat
    let onFractionChange: (CGFloat) -> Void

    /// Accumulated drag delta as a fraction of the timeline width (reset on gesture end).
    @GestureState private var dragDelta: CGFloat = 0

    private var displayFraction: CGFloat {
        max(0, min(1, fraction + dragDelta))
    }

    var body: some View {
        Image(systemName: isEntrance ? "chevron.right.to.line" : "chevron.left.to.line")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: min(44, timelineHeight))
            .background(isEntrance ? Color.green : Color.red)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: (isEntrance ? Color.green : Color.red).opacity(0.35), radius: 3, y: 2)
            .position(x: displayFraction * timelineWidth, y: timelineHeight / 2)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($dragDelta) { value, state, _ in
                        state = value.translation.width / timelineWidth
                    }
                    .onEnded { value in
                        let delta = value.translation.width / timelineWidth
                        let newFrac = max(0, min(1, fraction + delta))
                        onFractionChange(newFrac)
                    }
            )
    }
}
