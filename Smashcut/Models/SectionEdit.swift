import Foundation

// MARK: - Edit Status

/// Progressive editing status for a section.
enum EditStatus: String, Codable {
    case empty
    case hasMedia
    case marked
    case arranged
    case captioned
    case exported
}

// MARK: - Source Media

/// A single piece of source media (video or photo) in the media bin.
struct SourceMedia: Identifiable, Codable {
    var id: UUID = UUID()
    var url: URL
    var type: LayerType // .video or .photo
    var durationSeconds: Double = 0
    /// PHAsset local identifier, if imported from Photos library.
    var assetIdentifier: String?
    var addedAt: Date = Date()
}

// MARK: - Mark

/// A non-destructive in/out range on a source video.
struct Mark: Identifiable, Codable {
    var id: UUID = UUID()
    var sourceMediaID: UUID
    var inSeconds: Double
    var outSeconds: Double
    var label: String?

    var duration: Double { outSeconds - inSeconds }
}

// MARK: - Roll Layer

/// A layer within a roll, positioned spatially.
struct RollLayer: Identifiable, Codable {
    var id: UUID = UUID()
    /// Reference to the Mark this layer sources from (for video/photo clips).
    var markID: UUID?
    /// The compositing layer (position, z-index, filters, etc.).
    var layer: Layer
}

// MARK: - Roll

/// A timed container on the section timeline (A-roll, B-roll, etc.).
struct Roll: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String = "A-Roll"
    /// When this roll starts relative to the section timeline (seconds).
    var startOffset: Double = 0
    /// Duration of this roll on the section timeline.
    var duration: Double = 0
    /// Spatial layers within this roll (share the roll's timing window).
    var layers: [RollLayer] = []
}

// MARK: - Section Edit

/// Unified editing model for a section, replacing both ScriptSection and TimelineSegment.
struct SectionEdit: Identifiable, Codable {
    var id: UUID = UUID()
    var scriptText: String
    /// All source videos and photos for this section.
    var mediaBin: [SourceMedia] = []
    /// Multiple in/out ranges per source video.
    var marks: [Mark] = []
    /// A-roll, B-roll, etc. (timed containers on section timeline).
    var rolls: [Roll] = []
    /// Section-level captions tied to A-roll audio.
    var captionTimestamps: [CaptionTimestamp] = []
    /// Progressive editing status.
    var status: EditStatus = .empty
    /// Thumbnail data for list display.
    var previewThumbnailData: Data?

    init(scriptText: String) {
        self.scriptText = scriptText
    }

    /// Total section duration based on rolls.
    var duration: Double {
        rolls.map { $0.startOffset + $0.duration }.max() ?? 0
    }
}
