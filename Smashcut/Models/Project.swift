import Foundation

struct Project: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var rawIdea: String
    var script: Script?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(title: String, rawIdea: String) {
        self.title = title
        self.rawIdea = rawIdea
    }
}

class ProjectStore {
    static let shared = ProjectStore()

    private var fileURL: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("smashcut", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("projects.json")
    }

    func load() -> [Project] {
        guard let data = try? Data(contentsOf: fileURL),
              let projects = try? JSONDecoder().decode([Project].self, from: data) else {
            return []
        }
        return projects
    }

    func save(_ projects: [Project]) {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
