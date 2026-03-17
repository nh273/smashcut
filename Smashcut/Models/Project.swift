import Foundation

struct Project: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var rawIdea: String
    /// Legacy script model — migrated to `timeline` on first load.
    var script: Script?
    /// Layer-based timeline. Primary model going forward.
    var timeline: ProjectTimeline?
    /// Unified section editing model (replaces both script sections and timeline segments).
    var sectionEdits: [SectionEdit]?
    var linkedMediaIDs: [String] = []
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
              var projects = try? JSONDecoder().decode([Project].self, from: data) else {
            return []
        }
        // Migrate legacy script -> timeline on first load of old project data.
        var didMigrate = false
        for i in projects.indices where projects[i].timeline == nil {
            if let script = projects[i].script {
                projects[i].timeline = ProjectTimeline(migratingFrom: script)
                didMigrate = true
            }
        }
        // Migrate script sections -> sectionEdits for the new editing workflow.
        for i in projects.indices where projects[i].sectionEdits == nil {
            if let script = projects[i].script, !script.sections.isEmpty {
                projects[i].sectionEdits = script.sections.map { section in
                    SectionEditBridge.migrate(from: section)
                }
                didMigrate = true
            }
        }
        if didMigrate {
            save(projects)
        }
        return projects
    }

    func save(_ projects: [Project]) {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
