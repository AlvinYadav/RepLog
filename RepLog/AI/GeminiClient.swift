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
        UserDefaults.standard.string(forKey: "reportModel") ?? "gemini-flash-latest"
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
        jsonOutput: Bool = false
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
        if jsonOutput {
            generationConfig["response_mime_type"] = "application/json"
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
        request.timeoutInterval = 25

        // Free-tier models intermittently return 503 (overloaded) / 429 (rate limit)
        // or simply hang; all are transient, so retry with backoff before surfacing.
        var data = Data()
        var status = 0
        let attempts = 4
        for attempt in 0..<attempts {
            if attempt > 0 {
                try await Task.sleep(for: .seconds(pow(2.0, Double(attempt))))
            }
            do {
                (data, status) = try await Self.send(request)
            } catch let error as URLError
                where error.code == .timedOut || error.code == .networkConnectionLost {
                if attempt == attempts - 1 { throw error }
                continue
            }
            if status != 503 && status != 429 { break }
            // A 429 with "limit: 0" means the model has no free-tier quota at
            // all (e.g. Pro models) — retrying can never succeed.
            if status == 429, String(data: data, encoding: .utf8)?.contains("limit: 0") == true { break }
        }
        guard (200..<300).contains(status) else {
            throw GeminiError.badResponse(status, String(data: data.prefix(500), encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        guard let candidate = decoded.candidates?.first,
              let text = candidate.content?.parts?.compactMap(\.text).joined(),
              !text.isEmpty else {
            throw GeminiError.emptyCandidate
        }
        if let reason = candidate.finishReason, reason != "STOP" {
            // Keep the reply but flag abnormal termination (e.g. MAX_TOKENS) for diagnostics.
            return text + "\n/* finishReason: \(reason) */"
        }
        return text
    }

    private static func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Models available to the user's key that support generateContent.
    static func listAvailableModels() async throws -> [String] {
        guard let key = Keychain.get(Keychain.geminiAPIKey), !key.isEmpty else {
            throw GeminiError.missingAPIKey
        }
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=100")!)
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 20
        let (data, status) = try await send(request)
        guard (200..<300).contains(status) else {
            throw GeminiError.badResponse(status, String(data: data.prefix(500), encoding: .utf8) ?? "")
        }
        struct ModelList: Decodable {
            struct Model: Decodable {
                let name: String
                let supportedGenerationMethods: [String]?
            }
            let models: [Model]?
        }
        let list = try JSONDecoder().decode(ModelList.self, from: data)
        return (list.models ?? [])
            .filter { $0.supportedGenerationMethods?.contains("generateContent") ?? false }
            .map { $0.name.replacingOccurrences(of: "models/", with: "") }
            .sorted()
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
        let finishReason: String?
    }
    let candidates: [Candidate]?
}
