import SwiftUI

struct ScriptWorkshopView: View {
    @Environment(AppState.self) private var appState

    private let project: Project
    private let isNewProject: Bool

    /// For re-refining a project that already exists in AppState.
    init(project: Project) {
        self.project = project
        self.isNewProject = false
    }

    /// For a brand-new project — not yet saved, will be persisted only on accept.
    init(newTitle: String, rawIdea: String) {
        self.project = Project(title: newTitle.isEmpty ? "Untitled" : newTitle, rawIdea: rawIdea)
        self.isNewProject = true
    }

    @State private var vm = ScriptWorkshopViewModel()
    @State private var acceptedProject: Project?
    @State private var navigateToSections = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Idea")
                        .font(.headline)
                    Text(project.rawIdea)
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if vm.refinedScript == nil && !vm.isRefining {
                    Button {
                        Task { await vm.refineScript() }
                    } label: {
                        Label("Refine with Claude", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if vm.isRefining {
                    HStack {
                        ProgressView()
                        Text("Claude is refining your script…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }

                if let error = vm.refinementError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if let refined = vm.refinedScript {
                    ScriptRefinementView(
                        refinedScript: refined,
                        sections: $vm.sections,
                        onAccept: acceptScript
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Script Workshop")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            vm.rawIdea = project.rawIdea
        }
        // Navigate using the locally-stored accepted project — no appState lookup needed.
        .navigationDestination(isPresented: $navigateToSections) {
            if let p = acceptedProject {
                SectionManagerView(project: p)
            }
        }
    }

    private func acceptScript() {
        var updated = project
        updated.script = vm.buildScript(title: project.title)

        if isNewProject {
            // First-time save — only now does it appear in the project list.
            appState.addProject(updated)
        } else {
            appState.updateProject(updated)
        }

        // Store the result directly; don't rely on appState lookup for the push.
        acceptedProject = updated
        navigateToSections = true
    }
}
