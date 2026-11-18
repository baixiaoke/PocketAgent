import Foundation

/// OpenAI 兼容的 chat/completions 客户端（流式 + tool calling）。
/// DeepSeek / OpenAI / 任何兼容网关都能用，只改 baseURL 和 model。
final class LLMClient {

    enum ClientError: LocalizedError {
        case badURL(String)
        case missingKey
        case http(Int, String)
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .badURL(let s): return "接口地址不对：\(s)"
            case .missingKey: return "还没填 API Key（设置里填）"
            case .http(let code, let body): return "服务端 \(code)：\(body.prefix(400))"
            case .badResponse(let s): return "响应解析失败：\(s)"
            }
        }
    }

    struct Turn {
        var text: String = ""
        var toolCalls: [ToolCall] = []
        var finishReason: String?
    }

    // MARK: - SSE 增量结构
    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
                let tool_calls: [ToolCallDelta]?
            }
            let delta: Delta?
            let finish_reason: String?
        }
        let choices: [Choice]?
    }

    private struct ToolCallDelta: Decodable {
        let index: Int?
        let id: String?
        let function: FunctionDelta?
    }

    private struct FunctionDelta: Decodable {
        let name: String?
        let arguments: String?
    }

    // MARK: - 主入口
    func stream(
        settings: AgentSettings,
        apiKey: String,
        messages: [ChatMessage],
        tools: [ToolSpec],
        onDelta: @escaping (String) -> Void
    ) async throws -> Turn {

        guard !apiKey.isEmpty else { throw ClientError.missingKey }
        guard let url = Self.endpoint(from: settings.baseURL) else {
            throw ClientError.badURL(settings.baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: Self.body(settings: settings, messages: messages, tools: tools)
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.badResponse("没有 HTTP 响应")
        }
        if !(200..<300).contains(http.statusCode) {
            var raw = ""
            for try await line in bytes.lines { raw += line }
            throw ClientError.http(http.statusCode, raw)
        }

        var turn = Turn()
        var buffer: [Int: (id: String, name: String, args: String)] = [:]

        for try await line in bytes.lines {
            // SSE：空行是心跳，"data: ..." 是数据，"[DONE]" 是结束
            guard line.hasPrefix("data:") else { continue }
            var payload = line.dropFirst(5)
            if payload.hasPrefix(" ") { payload = payload.dropFirst() }
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(Chunk.self, from: data),
                  let choice = chunk.choices?.first else { continue }

            if let piece = choice.delta?.content, !piece.isEmpty {
                turn.text += piece
                onDelta(piece)
            }

            for tc in choice.delta?.tool_calls ?? [] {
                let idx = tc.index ?? 0
                var entry = buffer[idx] ?? (id: "", name: "", args: "")
                if let id = tc.id, !id.isEmpty { entry.id = id }
                if let name = tc.function?.name, !name.isEmpty { entry.name += name }
                if let args = tc.function?.arguments { entry.args += args }
                buffer[idx] = entry
            }

            if let finish = choice.finish_reason {
                turn.finishReason = finish
            }
        }

        turn.toolCalls = buffer.keys.sorted().compactMap { idx in
            guard let e = buffer[idx], !e.name.isEmpty else { return nil }
            let id = e.id.isEmpty ? "call_\(UUID().uuidString.prefix(8))" : e.id
            return ToolCall(id: id, function: FunctionCall(name: e.name, arguments: e.args))
        }
        return turn
    }

    // MARK: - 请求体
    static func endpoint(from base: String) -> URL? {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if !s.hasSuffix("/chat/completions") { s += "/chat/completions" }
        return URL(string: s)
    }

    static func body(settings: AgentSettings, messages: [ChatMessage], tools: [ToolSpec]) -> [String: Any] {
        var wire: [[String: Any]] = []

        for m in messages {
            switch m.role {
            case .assistant:
                var d: [String: Any] = ["role": "assistant"]
                d["content"] = m.content.isEmpty ? NSNull() : m.content
                if let calls = m.toolCalls, !calls.isEmpty {
                    d["tool_calls"] = calls.map {
                        ["id": $0.id,
                         "type": "function",
                         "function": ["name": $0.function.name, "arguments": $0.function.arguments]]
                    }
                }
                wire.append(d)
            case .tool:
                wire.append([
                    "role": "tool",
                    "tool_call_id": m.toolCallID ?? "",
                    "content": m.content,
                ])
            case .system, .user:
                wire.append(["role": m.role.rawValue, "content": m.content])
            }
        }

        var body: [String: Any] = [
            "model": settings.model,
            "messages": wire,
            "stream": true,
            "temperature": settings.temperature,
        ]
        if !tools.isEmpty {
            body["tools"] = tools.map { spec -> [String: Any] in
                ["type": "function",
                 "function": ["name": spec.name,
                              "description": spec.description,
                              "parameters": spec.parameters]]
            }
            body["tool_choice"] = "auto"
        }
        return body
    }
}
