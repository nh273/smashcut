import Foundation

// MARK: - Layer Types

enum LayerType: String, Codable {
    case video
    case photo
    case text
}

enum FilterPreset: String, Codable {
    case none
    case vivid
    case matte
    case noir
    case fade
}

/// Cache state for pre-rendered layer assets.
enum CacheState: Codable, Equatable {
    case none
    case processing(progress: Double)
    case ready
    case stale
}

// MARK: - Normalized Position

/// A rectangle in normalized coordinates (0…1 in both dimensions).
struct NormalizedRect: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    /// Covers the full frame.
    static let fullFrame = NormalizedRect(x: 0, y: 0, width: 1, height: 1)
}

// MARK: - Layer

/// A single media layer within a timeline segment.
struct Layer: Identifiable, Codable {
    var id: UUID = UUID()
    /// Media type for this layer.
    var type: LayerType
    /// Source file URL. nil for text layers.
    var sourceURL: URL?
    /// Normalized position within the composition frame (0…1).
    var position: NormalizedRect = .fullFrame
    /// Stacking order — higher values appear on top.
    var zIndex: Int = 0
    var trimStartSeconds: Double?
    var trimEndSeconds: Double?
    /// Audio volume (0–1).
    var volume: Double = 1.0
    var filter: FilterPreset = .none
    var hasBackgroundRemoval: Bool = false
    /// URL to pre-rendered cached asset (bg removal output). Used by compositor to skip live processing.
    var cachedProcessedURL: URL?
    /// Current cache state for this layer's expensive operations.
    var cacheState: CacheState = .none
    /// Time offset of this layer from the start of its segment (seconds).
    var startOffset: Double = 0
    /// Border width in points (rendered by compositor).
    var borderWidth: Double = 0
    /// Corner radius in points (rendered by compositor).
    var cornerRadius: Double = 0

    init(
        type: LayerType,
        sourceURL: URL? = nil,
        position: NormalizedRect = .fullFrame,
        zIndex: Int = 0,
        trimStartSeconds: Double? = nil,
        trimEndSeconds: Double? = nil,
        volume: Double = 1.0,
        filter: FilterPreset = .none,
        hasBackgroundRemoval: Bool = false,
        cachedProcessedURL: URL? = nil,
        cacheState: CacheState = .none,
        startOffset: Double = 0,
        borderWidth: Double = 0,
        cornerRadius: Double = 0
    ) {
        self.type = type
        self.sourceURL = sourceURL
        self.position = position
        self.zIndex = zIndex
        self.trimStartSeconds = trimStartSeconds
        self.trimEndSeconds = trimEndSeconds
        self.volume = volume
        self.filter = filter
        self.hasBackgroundRemoval = hasBackgroundRemoval
        self.cachedProcessedURL = cachedProcessedURL
        self.cacheState = cacheState
        self.startOffset = startOffset
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
    }

    /// Whether this layer needs expensive pre-rendering (background removal).
    var needsCaching: Bool {
        hasBackgroundRemoval && type == .video
    }

    /// Mark cache as stale, clearing the cached URL.
    mutating func invalidateCache() {
        guard cacheState != .none else { return }
        cacheState = .stale
        cachedProcessedURL = nil
    }
}

// MARK: - TextLayer

/// A text overlay with caption styling and timing, composing a base Layer.
struct TextLayer: Identifiable, Codable {
    var id: UUID = UUID()
    /// Base layer for position and z-ordering.
    var layer: Layer
    var text: String
    var style: CaptionStyle = CaptionStyle()
    var startSeconds: Double = 0
    var endSeconds: Double = 0

    init(
        layer: Layer,
        text: String,
        style: CaptionStyle = CaptionStyle(),
        startSeconds: Double = 0,
        endSeconds: Double = 0
    ) {
        self.layer = layer
        self.text = text
        self.style = style
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
}

// MARK: - TimelineSegment

/// Replaces ScriptSection. A paragraph of script with associated media and text layers.
struct TimelineSegment: Identifiable, Codable {
    var id: UUID = UUID()
    var scriptText: String
    var duration: Double = 0
    var layers: [Layer] = []
    var textLayers: [TextLayer] = []

    init(scriptText: String) {
        self.scriptText = scriptText
    }
}

extension TimelineSegment {
    /// Split a segment into two at `localTime` (seconds from segment start).
    /// Layers and text layers are distributed/trimmed to the appropriate half.
    static func split(_ segment: TimelineSegment, at localTime: Double) -> (left: TimelineSegment, right: TimelineSegment) {
        var left = TimelineSegment(scriptText: segment.scriptText)
        left.duration = localTime

        var right = TimelineSegment(scriptText: segment.scriptText)
        right.duration = segment.duration - localTime

        // Split layers
        for layer in segment.layers {
            let layerStart = layer.startOffset
            let trimStart = layer.trimStartSeconds ?? 0
            let trimEnd = layer.trimEndSeconds ?? segment.duration
            let layerEnd = layerStart + (trimEnd - trimStart)

            // Layer spans left half
            if layerStart < localTime {
                var l = layer
                l.id = UUID()
                l.trimEndSeconds = trimStart + min(localTime - layerStart, trimEnd - trimStart)
                left.layers.append(l)
            }

            // Layer spans right half
            if layerEnd > localTime {
                var r = layer
                r.id = UUID()
                if localTime > layerStart {
                    r.trimStartSeconds = trimStart + (localTime - layerStart)
                    r.startOffset = 0
                } else {
                    r.startOffset = layerStart - localTime
                }
                right.layers.append(r)
            }
        }

        // Split text layers
        for textLayer in segment.textLayers {
            if textLayer.endSeconds <= localTime {
                left.textLayers.append(textLayer)
            } else if textLayer.startSeconds >= localTime {
                var t = textLayer
                t.startSeconds -= localTime
                t.endSeconds -= localTime
                right.textLayers.append(t)
            } else {
                // Spans the split — duplicate to both sides
                var tLeft = textLayer
                tLeft.id = UUID()
                tLeft.endSeconds = localTime
                left.textLayers.append(tLeft)

                var tRight = textLayer
                tRight.id = UUID()
                tRight.startSeconds = 0
                tRight.endSeconds = textLayer.endSeconds - localTime
                right.textLayers.append(tRight)
            }
        }

        return (left, right)
    }
}

// MARK: - ProjectTimeline

/// Replaces Script. The top-level timeline model for a project.
struct ProjectTimeline: Codable {
    var segments: [TimelineSegment]

    init(segments: [TimelineSegment] = []) {
        self.segments = segments
    }
}

// MARK: - Migration from Script

extension ProjectTimeline {
    /// Wraps a legacy Script into a ProjectTimeline.
    /// Each ScriptSection with a Recording becomes a TimelineSegment with a single
    /// video Layer at zIndex 0. Caption timestamps become TextLayers at zIndex 10.
    init(migratingFrom script: Script) {
        self.segments = script.sections.map { section in
            var segment = TimelineSegment(scriptText: section.text)
            segment.duration = section.recording?.durationSeconds ?? 0

            if let recording = section.recording {
                let videoLayer = Layer(
                    type: .video,
                    sourceURL: recording.rawVideoURL,
                    zIndex: 0,
                    trimStartSeconds: recording.trimStartSeconds,
                    trimEndSeconds: recording.trimEndSeconds,
                    hasBackgroundRemoval: recording.backgroundMediaURL != nil
                )
                segment.layers = [videoLayer]

                segment.textLayers = recording.captionTimestamps.map { ts in
                    let baseLayer = Layer(
                        type: .text,
                        position: NormalizedRect(x: 0, y: ts.verticalPosition, width: 1, height: 0.1),
                        zIndex: 10
                    )
                    return TextLayer(
                        layer: baseLayer,
                        text: ts.text,
                        style: ts.style,
                        startSeconds: ts.startSeconds,
                        endSeconds: ts.endSeconds
                    )
                }
            }
            return segment
        }
    }
}
