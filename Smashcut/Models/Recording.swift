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
}

struct CaptionTimestamp: Identifiable, Codable {
    var id: UUID = UUID()
    var text: String
    var startSeconds: Double
    var endSeconds: Double
}
