import Foundation

struct Recording: Identifiable, Codable {
    var id: UUID = UUID()
    var sectionID: UUID
    var rawVideoURL: URL
    var processedVideoURL: URL?
    var compositeVideoURL: URL?
    var backgroundMediaURL: URL?
    var backgroundIsVideo: Bool = false
    var captionTimestamps: [CaptionTimestamp] = []
    var durationSeconds: Double = 0
    var trimStartSeconds: Double? = nil
    var trimEndSeconds: Double? = nil
}

/// RGBA color stored as Double components for Codable compatibility.
struct CaptionColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let white = CaptionColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let black = CaptionColor(red: 0, green: 0, blue: 0, alpha: 1)
    static let yellow = CaptionColor(red: 1, green: 1, blue: 0, alpha: 1)
}

enum ContrastMode: String, Codable {
    case none
    case stroke
    case highlight
    case shadow
}

struct CaptionStyle: Codable {
    var fontName: String = "Helvetica-Bold"
    var fontSize: Double = 44
    var textColor: CaptionColor = .white
    var contrastMode: ContrastMode = .shadow
}

struct CaptionTimestamp: Identifiable, Codable {
    var id: UUID = UUID()
    var text: String
    var startSeconds: Double
    var endSeconds: Double
    /// Normalized vertical position from top (0 = top, 1 = bottom).
    var verticalPosition: Double = 0.82
    var style: CaptionStyle = CaptionStyle()
}
