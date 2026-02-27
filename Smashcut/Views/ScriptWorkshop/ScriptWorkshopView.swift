import SwiftUI

struct ScriptWorkshopView: View {
    @Environment(AppState.self) private var appState
    let project: Project

    @State private var vm = ScriptWorkshopViewModel()
    @State private var navigateToSections = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Raw idea display
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Idea")
                        .font(.headline)
                    Text(project.rawIdea)
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Refine button
                if vm.refinedScript == nil && !vm.isRefining {
                    Button {
                        Task { await vm.refineScript() }
                    } label: {
                        Label("Refine with Claude", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Loading
                if vm.isRefining {
                    HStack {
                        ProgressView()
                        Text("Claude is refining your script…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }

                // Error
                if let error = vm.refinementError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Refined output
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
        .navigationDestination(isPresented: $navigateToSections) {
            if let script = appState.projects.first(where: { $0.id == project.id })?.script {
                SectionManagerView(project: appState.projects.first(where: { $0.id == project.id })!)
            }
        }
    }

    private func acceptScript() {
        var updated = project
        let script = vm.buildScript(title: project.title)
        updated.script = script
        appState.updateProject(updated)
        navigateToSections = true
    }
}
