import Foundation

struct Script: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var rawIdea: String
    var refinedText: String?
    var sections: [ScriptSection]

    init(title: String, rawIdea: String) {
        self.title = title
        self.rawIdea = rawIdea
        self.sections = []
    }
}

struct ScriptSection: Identifiable, Codable {
    var id: UUID = UUID()
    var index: Int
    var text: String
    var recording: Recording?
    var status: SectionStatus

    enum SectionStatus: String, Codable {
        case unrecorded
        case recorded
        case processed
        case exported
    }

    init(index: Int, text: String) {
        self.index = index
        self.text = text
        self.status = .unrecorded
    }
}
