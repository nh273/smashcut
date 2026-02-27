import SwiftUI

struct SectionManagerView: View {
    @Environment(AppState.self) private var appState
    var project: Project

    var currentProject: Project {
        appState.projects.first(where: { $0.id == project.id }) ?? project
    }

    var body: some View {
        Group {
            if let script = currentProject.script, !script.sections.isEmpty {
                List(script.sections) { section in
                    SectionRowView(
                        section: section,
                        project: currentProject
                    )
                }
            } else {
                ContentUnavailableView {
                    Label("No Sections", systemImage: "doc.text")
                } description: {
                    Text("Refine your script to generate sections.")
                } actions: {
                    NavigationLink("Refine Script") {
                        ScriptWorkshopView(project: currentProject)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(currentProject.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
