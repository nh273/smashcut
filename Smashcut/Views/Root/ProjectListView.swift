import SwiftUI

struct ProjectListView: View {
    @Environment(AppState.self) private var appState
    @State private var showingNewProject = false
    @State private var newProjectTitle = ""
    @State private var newProjectIdea = ""

    var body: some View {
        Group {
            if appState.projects.isEmpty {
                ContentUnavailableView {
                    Label("No Projects", systemImage: "film.stack")
                } description: {
                    Text("Create your first video project to get started.")
                } actions: {
                    Button("New Project") { showingNewProject = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(appState.projects) { project in
                        NavigationLink {
                            SectionManagerView(project: project)
                        } label: {
                            ProjectRowView(project: project)
                        }
                    }
                    .onDelete(perform: deleteProjects)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !appState.projects.isEmpty {
                    EditButton()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button {
                        showingNewProject = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheet(isPresented: $showingNewProject)
        }
    }

    private func deleteProjects(at offsets: IndexSet) {
        offsets.forEach { idx in
            appState.deleteProject(appState.projects[idx])
        }
    }
}

struct ProjectRowView: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.title)
                .font(.headline)
            if let script = project.script {
                let total = script.sections.count
                let done = script.sections.filter { $0.status != .unrecorded }.count
                Text("\(done)/\(total) sections complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Script not yet refined")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct NewProjectSheet: View {
    @Binding var isPresented: Bool

    @State private var title = ""
    @State private var idea = ""
    @State private var navigateToWorkshop = false

    var body: some View {
        NavigationStack {
            List {
                Section("Project Title") {
                    TextField("e.g. My Product Demo", text: $title)
                }
                Section {
                    TextField("Describe what you want to talk about…", text: $idea, axis: .vertical)
                        .lineLimit(4...12)
                } header: {
                    Text("Script Idea")
                } footer: {
                    Text("Claude will refine this into a polished script with sections.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") {
                        navigateToWorkshop = true
                    }
                    .disabled(idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            // Project is NOT created here — ScriptWorkshopView creates it only on accept.
            .navigationDestination(isPresented: $navigateToWorkshop) {
                ScriptWorkshopView(newTitle: title, rawIdea: idea)
            }
        }
    }
}
