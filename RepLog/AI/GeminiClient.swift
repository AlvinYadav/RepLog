import Foundation

enum GeminiError: LocalizedError {
    case missingAPIKey
    case badResponse(Int, String)
    case emptyCandidate

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "No Gemini API key set. Add one in Settings."
        case .badResponse(let code, let body): return "Gemini API error \(code): \(body)"
        case .emptyCandidate: return "Gemini returned no content."
        }
    }
}

/// Minimal REST client for the Gemini generateContent endpoint.
/// Requests are built as JSON dictionaries; only the response is strongly typed.
struct GeminiClient {
    var model: String

    static var defaultParseModel: String {
        UserDefaults.standard.string(forKey: "parseModel") ?? "gemini-flash-latest"
    }
    static var defaultReportModel: String {
        UserDefaults.standard.string(forKey: "reportModel") ?? "gemini-pro-latest"
    }

    struct InlineImage {
        let mimeType: String
        let data: Data
    }

    /// Sends a generateContent request and returns the first candidate's text.
    func generate(
        system: String,
        user: String,
        image: InlineImage? = nil,
        responseSchema: [String: Any]? = nil
    ) async throws -> String {
        guard let key = Keychain.get(Keychain.geminiAPIKey), !key.isEmpty else {
            throw GeminiError.missingAPIKey
        }

        var parts: [[String: Any]] = [["text": user]]
        if let image {
            parts.append([
                "inline_data": [
                    "mime_type": image.mimeType,
                    "data": image.data.base64EncodedString()
                ]
            ])
        }

        var generationConfig: [String: Any] = ["temperature": 0.2]
        if let responseSchema {
            generationConfig["response_mime_type"] = "application/json"
            generationConfig["response_schema"] = responseSchema
        }

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": generationConfig
        ]

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw GeminiError.badResponse(status, String(data: data.prefix(500), encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        guard let text = decoded.candidates?.first?.content?.parts?.compactMap(\.text).joined(),
              !text.isEmpty else {
            throw GeminiError.emptyCandidate
        }
        return text
    }

    /// Quick connectivity check used by the Settings "Test" button.
    static func testConnection(model: String) async -> Result<String, Error> {
        do {
            let reply = try await GeminiClient(model: model)
                .generate(system: "Reply with the single word: ok", user: "ping")
            return .success(reply.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return .failure(error)
        }
    }
}

private struct GenerateContentResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable { let text: String? }
            let parts: [Part]?
        }
        let content: Content?
    }
    let candidates: [Candidate]?
}
