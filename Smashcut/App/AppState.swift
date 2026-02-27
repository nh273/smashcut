import Foundation
import Observation

@Observable
class AppState {
    var projects: [Project] = []
    var selectedProjectID: UUID?
    var isSettingsPresented = false

    var hasAPIKey: Bool = KeychainService.shared.retrieveAPIKey() != nil

    init() {
        loadProjects()
    }

    func saveAPIKey(_ key: String) {
        KeychainService.shared.saveAPIKey(key)
        hasAPIKey = true
    }

    func clearAPIKey() {
        KeychainService.shared.deleteAPIKey()
        hasAPIKey = false
    }

    func loadProjects() {
        projects = ProjectStore.shared.load()
    }

    func saveProjects() {
        ProjectStore.shared.save(projects)
    }

    /// Creates and immediately persists a project (used when re-refining an existing project).
    func createProject(title: String, rawIdea: String) -> Project {
        let project = Project(title: title, rawIdea: rawIdea)
        projects.append(project)
        saveProjects()
        return project
    }

    /// Persists a fully-built project for the first time (used after script refinement).
    func addProject(_ project: Project) {
        projects.append(project)
        saveProjects()
    }

    func updateProject(_ updated: Project) {
        if let idx = projects.firstIndex(where: { $0.id == updated.id }) {
            var p = updated
            p.updatedAt = Date()
            projects[idx] = p
            saveProjects()
        }
    }

    func deleteProject(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        saveProjects()
    }
}
