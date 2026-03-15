import SwiftUI

struct SectionRefineSheet: View {
    let section: ScriptSection
    let project: Project

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var direction = ""
    @State private var refinedText: String?
    @State private var isRefining = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Text")
                            .font(.headline)
                        Text(section.text)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Direction (optional)")
                            .font(.headline)
                        TextField(
                            "e.g. make it more conversational, add a hook…",
                            text: $direction,
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                        .padding(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.systemGray4))
                        )
                    }

                    if isRefining {
                        HStack {
                            ProgressView()
                            Text("Refining…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }

                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if let refined = refinedText {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Refined Text")
                                .font(.headline)
                            Text(refined)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.accentColor.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        Button { acceptRefinement(refined) } label: {
                            Label("Accept Refinement", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("acceptRefinement_\(section.index)")
                    }

                    if refinedText == nil && !isRefining {
                        Button { refine() } label: {
                            Label("Refine with Claude", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("refineSectionButton_\(section.index)")
                    }
                }
                .padding()
            }
            .navigationTitle("Refine Section \(section.index + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func refine() {
        isRefining = true
        error = nil
        refinedText = nil
        Task {
            do {
                let result = try await ClaudeService.shared.refineSectionText(
                    currentText: section.text,
                    direction: direction
                )
                await MainActor.run {
                    refinedText = result
                    isRefining = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isRefining = false
                }
            }
        }
    }

    private func acceptRefinement(_ refined: String) {
        var updatedProject = project
        if var script = updatedProject.script,
           let idx = script.sections.firstIndex(where: { $0.id == section.id }) {
            script.sections[idx].text = refined
            updatedProject.script = script
        }
        appState.updateProject(updatedProject)
        dismiss()
    }
}
