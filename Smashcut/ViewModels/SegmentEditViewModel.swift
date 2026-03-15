import AVFoundation
import Observation
import UIKit

@Observable
class SegmentEditViewModel {
    var segment: TimelineSegment
    let segmentIndex: Int

    // Playback
    let player = AVPlayer()
    var isPlaying = false
    var currentTime: Double = 0
    var duration: Double = 0

    // Selection
    var selectedLayerID: UUID?
    var selectedTextLayerID: UUID?

    // Layer trim sheet
    var trimLayerID: UUID?

    // Grid snapping
    var showGrid = false

    private var timeObserver: Any?
    private var buildTask: Task<Void, Never>?

    init(segment: TimelineSegment, segmentIndex: Int) {
        self.segment = segment
        self.segmentIndex = segmentIndex
        self.duration = segment.duration
        setupTimeObserver()
        rebuildComposition()
    }

    // MARK: - Playback

    func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, duration))
        currentTime = clamped
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func teardown() {
        player.pause()
        buildTask?.cancel()
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
            timeObserver = nil
        }
    }

    // MARK: - Layer Selection

    func selectLayer(_ id: UUID) {
        selectedLayerID = id
        selectedTextLayerID = nil
    }

    func selectTextLayer(_ id: UUID) {
        selectedTextLayerID = id
        selectedLayerID = nil
    }

    func clearSelection() {
        selectedLayerID = nil
        selectedTextLayerID = nil
    }

    // MARK: - Layer Reordering

    func moveLayer(from source: IndexSet, to destination: Int) {
        segment.layers.move(fromOffsets: source, toOffset: destination)
        // Update z-indices to match visual order (top of list = highest z)
        for i in segment.layers.indices {
            segment.layers[i].zIndex = segment.layers.count - 1 - i
        }
        rebuildComposition()
    }

    func moveTextLayer(from source: IndexSet, to destination: Int) {
        segment.textLayers.move(fromOffsets: source, toOffset: destination)
        for i in segment.textLayers.indices {
            segment.textLayers[i].layer.zIndex = segment.textLayers.count - 1 - i + 10
        }
        rebuildComposition()
    }

    // MARK: - Layer Property Updates

    func toggleBackgroundRemoval(layerID: UUID) {
        guard let idx = segment.layers.firstIndex(where: { $0.id == layerID }) else { return }
        segment.layers[idx].hasBackgroundRemoval.toggle()

        if segment.layers[idx].hasBackgroundRemoval {
            // Kick off background pre-rendering
            Task {
                await LayerAssetCache.shared.prerender(
                    layer: segment.layers[idx],
                    onProgress: { _ in },
                    onComplete: { [weak self] url in
                        guard let self,
                              let i = self.segment.layers.firstIndex(where: { $0.id == layerID }) else { return }
                        if let url {
                            self.segment.layers[i].cachedProcessedURL = url
                            self.segment.layers[i].cacheState = .ready
                        }
                        self.rebuildComposition()
                    }
                )
            }
        } else {
            segment.layers[idx].cacheState = .none
            segment.layers[idx].cachedProcessedURL = nil
        }
        rebuildComposition()
    }

    func setFilter(layerID: UUID, filter: FilterPreset) {
        guard let idx = segment.layers.firstIndex(where: { $0.id == layerID }) else { return }
        segment.layers[idx].filter = filter
        rebuildComposition()
    }

    func setVolume(layerID: UUID, volume: Double) {
        guard let idx = segment.layers.firstIndex(where: { $0.id == layerID }) else { return }
        segment.layers[idx].volume = max(0, min(1, volume))
        rebuildComposition()
    }

    func setBorderWidth(layerID: UUID, width: Double) {
        guard let idx = segment.layers.firstIndex(where: { $0.id == layerID }) else { return }
        segment.layers[idx].borderWidth = max(0, width)
        rebuildComposition()
    }

    func setCornerRadius(layerID: UUID, radius: Double) {
        guard let idx = segment.layers.firstIndex(where: { $0.id == layerID }) else { return }
        segment.layers[idx].cornerRadius = max(0, radius)
        rebuildComposition()
    }

    func setLayerTrim(layerID: UUID, start: Double?, end: Double?) {
        guard let idx = segment.layers.firstIndex(where: { $0.id == layerID }) else { return }
        segment.layers[idx].trimStartSeconds = start
        segment.layers[idx].trimEndSeconds = end
        segment.markCacheStale(layerID: layerID)
        rebuildComposition()
    }

    // MARK: - Layer Position (drag on canvas)

    func updateLayerPosition(layerID: UUID, position: NormalizedRect) {
        if let idx = segment.layers.firstIndex(where: { $0.id == layerID }) {
            segment.layers[idx].position = snapToGrid(position)
            rebuildComposition()
        }
    }

    func updateTextLayerPosition(textLayerID: UUID, position: NormalizedRect) {
        if let idx = segment.textLayers.firstIndex(where: { $0.id == textLayerID }) {
            segment.textLayers[idx].layer.position = snapToGrid(position)
            rebuildComposition()
        }
    }

    // MARK: - Text Layer Properties

    func setTextLayerText(id: UUID, text: String) {
        guard let idx = segment.textLayers.firstIndex(where: { $0.id == id }) else { return }
        segment.textLayers[idx].text = text
        rebuildComposition()
    }

    func setTextLayerFontSize(id: UUID, size: Double) {
        guard let idx = segment.textLayers.firstIndex(where: { $0.id == id }) else { return }
        segment.textLayers[idx].style.fontSize = max(12, min(120, size))
        rebuildComposition()
    }

    func setTextLayerColor(id: UUID, color: CaptionColor) {
        guard let idx = segment.textLayers.firstIndex(where: { $0.id == id }) else { return }
        segment.textLayers[idx].style.textColor = color
        rebuildComposition()
    }

    func setTextLayerContrastMode(id: UUID, mode: ContrastMode) {
        guard let idx = segment.textLayers.firstIndex(where: { $0.id == id }) else { return }
        segment.textLayers[idx].style.contrastMode = mode
        rebuildComposition()
    }

    func setTextLayerFontName(id: UUID, fontName: String) {
        guard let idx = segment.textLayers.firstIndex(where: { $0.id == id }) else { return }
        segment.textLayers[idx].style.fontName = fontName
        rebuildComposition()
    }

    // MARK: - Add Layers

    func addTextLayer() {
        let baseLayer = Layer(
            type: .text,
            position: NormalizedRect(x: 0.1, y: 0.7, width: 0.8, height: 0.15),
            zIndex: 10 + segment.textLayers.count
        )
        let textLayer = TextLayer(
            layer: baseLayer,
            text: "New Text",
            startSeconds: 0,
            endSeconds: duration
        )
        segment.textLayers.append(textLayer)
        selectedTextLayerID = textLayer.id
        selectedLayerID = nil
        rebuildComposition()
    }

    func deleteTextLayer(id: UUID) {
        segment.textLayers.removeAll { $0.id == id }
        if selectedTextLayerID == id { selectedTextLayerID = nil }
        rebuildComposition()
    }

    // MARK: - Grid Snapping

    private func snapToGrid(_ rect: NormalizedRect) -> NormalizedRect {
        guard showGrid else { return rect }
        let snapThreshold = 0.02
        var snapped = rect

        // Snap to thirds
        let thirds: [Double] = [0, 1.0 / 3.0, 2.0 / 3.0, 1.0]
        for third in thirds {
            if abs(snapped.x - third) < snapThreshold { snapped.x = third }
            if abs(snapped.y - third) < snapThreshold { snapped.y = third }
            if abs(snapped.x + snapped.width - third) < snapThreshold {
                snapped.x = third - snapped.width
            }
            if abs(snapped.y + snapped.height - third) < snapThreshold {
                snapped.y = third - snapped.height
            }
        }
        // Clamp
        snapped.x = max(0, min(1 - snapped.width, snapped.x))
        snapped.y = max(0, min(1 - snapped.height, snapped.y))

        return snapped
    }

    // MARK: - Composition

    func rebuildComposition() {
        buildTask?.cancel()
        buildTask = Task { @MainActor in
            do {
                let result = try await LiveCompositionBuilder.build(segment: segment)
                let item = AVPlayerItem(asset: result.composition)
                item.videoComposition = result.videoComposition
                item.audioMix = result.audioMix

                let wasPlaying = isPlaying
                let savedTime = currentTime
                player.replaceCurrentItem(with: item)
                seek(to: savedTime)
                if wasPlaying { player.play() }

                // Update duration from composition
                let compDuration = try await result.composition.load(.duration).seconds
                if compDuration > 0 { duration = compDuration }
            } catch {
                // Fallback: load first video layer directly
                if let firstVideo = segment.layers.first(where: { $0.type == .video }),
                   let url = firstVideo.sourceURL {
                    player.replaceCurrentItem(with: AVPlayerItem(url: url))
                }
            }
        }
    }

    // MARK: - Private

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.033, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let t = max(0, time.seconds)
            self.currentTime = t
            if self.duration > 0 && t >= self.duration {
                self.player.pause()
                self.isPlaying = false
            }
        }
    }
}
