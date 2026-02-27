import Foundation

actor ClaudeService {
    static let shared = ClaudeService()

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-opus-4-6"

    struct ScriptResult {
        let refinedScript: String
        let sections: [String]
    }

    func refineScript(rawIdea: String) async throws -> ScriptResult {
        guard let apiKey = KeychainService.shared.retrieveAPIKey() else {
            throw ClaudeError.noAPIKey
        }

        let systemPrompt = """
        You are a script writing assistant for short-form video narration.
        Given a script idea, refine it into a polished narration script and break it into \
        sections. Each section should be 2-4 sentences, suitable for a single take recording.

        Respond ONLY with valid JSON in this exact format:
        {
            "refinedScript": "The complete refined script text",
            "sections": ["Section 1 text", "Section 2 text", ...]
        }
        """

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": "Here is my script idea:\n\n\(rawIdea)"]
            ]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            if let body = String(data: data, encoding: .utf8) {
                throw ClaudeError.apiError("Status \((response as? HTTPURLResponse)?.statusCode ?? 0): \(body)")
            }
            throw ClaudeError.apiError("Request failed")
        }

        struct ClaudeAPIResponse: Codable {
            struct Content: Codable {
                let type: String
                let text: String
            }
            let content: [Content]
        }

        let claudeResponse = try JSONDecoder().decode(ClaudeAPIResponse.self, from: data)
        guard let textContent = claudeResponse.content.first(where: { $0.type == "text" })?.text else {
            throw ClaudeError.invalidResponse
        }

        // Parse JSON from Claude's text content
        if let jsonData = textContent.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let refinedScript = json["refinedScript"] as? String,
           let sections = json["sections"] as? [String] {
            return ScriptResult(refinedScript: refinedScript, sections: sections)
        }

        // Fallback: return raw text as single section
        return ScriptResult(refinedScript: textContent, sections: [textContent])
    }

    enum ClaudeError: LocalizedError {
        case noAPIKey
        case apiError(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No API key configured. Please add your Anthropic API key in Settings."
            case .apiError(let msg):
                return "Claude API error: \(msg)"
            case .invalidResponse:
                return "Could not parse Claude's response."
            }
        }
    }
}
