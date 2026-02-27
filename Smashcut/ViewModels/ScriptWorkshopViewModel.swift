import Foundation
import Observation

@Observable
class ScriptWorkshopViewModel {
    var rawIdea: String = ""
    var isRefining = false
    var refinementError: String?
    var refinedScript: String?
    var sections: [String] = []

    func refineScript() async {
        guard !rawIdea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isRefining = true
        refinementError = nil

        do {
            let result = try await ClaudeService.shared.refineScript(rawIdea: rawIdea)
            await MainActor.run {
                self.refinedScript = result.refinedScript
                self.sections = result.sections
                self.isRefining = false
            }
        } catch {
            await MainActor.run {
                self.refinementError = error.localizedDescription
                self.isRefining = false
            }
        }
    }

    func buildScript(title: String) -> Script {
        var script = Script(title: title, rawIdea: rawIdea)
        script.refinedText = refinedScript
        script.sections = sections.enumerated().map { idx, text in
            ScriptSection(index: idx, text: text)
        }
        return script
    }

    func reset() {
        rawIdea = ""
        isRefining = false
        refinementError = nil
        refinedScript = nil
        sections = []
    }
}
