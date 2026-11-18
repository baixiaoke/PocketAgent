// ─────────────────────────────────────────────────────────────
// PocketAgent · Swift Playgrounds 单文件版
//
// 用法：Playgrounds 新建 App → 打开 ContentView.swift → 全选删掉 → 粘贴本文件 → 点 ▶
// 不要删 MyApp.swift（那个文件里有 @main，留着它才能启动）。
//
// 与 Xcode 版的差别：
//   · API Key 存 UserDefaults（Playgrounds 不能改 Info.plist，Keychain 偶发被重置）
//   · 去掉了「提醒事项」工具（需要 Info.plist 权限声明，缺了会崩）
//   · 其余 9 个原生工具全在
// ─────────────────────────────────────────────────────────────

import SwiftUI
import UIKit
import Foundation
import UserNotifications

// ═════════════════════════════════════════════════════════════
// MARK: - 数据模型
// ═════════════════════════════════════════════════════════════

enum Role: String, Codable {
    case system, user, assistant, tool
}

struct FunctionCall: Codable, Hashable {
    var name: String
    var arguments: String
}

struct ToolCall: Codable, Hashable, Identifiable {
    var id: String
    var type: String = "function"
    var function: FunctionCall
}

struct ChatMessage: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var role: Role
    var content: String = ""
    var toolCalls: [ToolCall]? = nil
    var toolCallID: String? = nil
    var toolName: String? = nil
    var createdAt: Date = Date()

    static func system(_ s: String) -> ChatMessage { .init(role: .system, content: s) }
    static func user(_ s: String) -> ChatMessage { .init(role: .user, content: s) }
    static func assistant(_ s: String, calls: [ToolCall]? = nil) -> ChatMessage {
        .init(role: .assistant, content: s, toolCalls: calls)
    }
    static func tool(_ s: String, id: String, name: String) -> ChatMessage {
        .init(role: .tool, content: s, toolCallID: id, toolName: name)
    }
}

struct ToolSpec {
    let name: String
    let description: String
    let parameters: [String: Any]
}

struct ChatSession: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var title: String = "新对话"
    var messages: [ChatMessage] = []
    var updatedAt: Date = Date()
}

struct AgentSettings: Codable, Equatable {
    var baseURL: String = "https://api.deepseek.com"
    var model: String = "deepseek-chat"
    var systemPrompt: String = """
    你是运行在这台 iPhone 上的独立 agent，名字叫「小椒」。
    你能直接操作这台设备的原生能力：读写 App 沙盒里的文件、抓网页、剪贴板、打开链接、发通知。
    规则：
    1. 需要事实或最新信息时用 http_get，不要凭记忆编。
    2. 需要落盘的内容用 write_file，不要只在回复里说。
    3. 一次只调一个工具，拿到结果再决定下一步。
    4. 回答用简体中文，直接给结论，不要客套。
    """
    var maxRounds: Int = 8
    var temperature: Double = 0.7
}

// ═════════════════════════════════════════════════════════════
// MARK: - 本地存储（Playgrounds 版用 UserDefaults）
// ═════════════════════════════════════════════════════════════

final class Store {
    static let shared = Store()

    private let settingsKey = "pa.settings"
    private let apiKeyKey = "pa.apikey"
    private let sessionsFileName = "sessions.json"

    private(set) var sessions: [ChatSession] = []
    private(set) var settings = AgentSettings()
    private(set) var apiKey: String = ""

    private init() { load() }

    var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var sessionsURL: URL { documentsDirectory.appendingPathComponent(sessionsFileName) }

    func load() {
        if let data = try? Data(contentsOf: sessionsURL),
           let list = try? JSONDecoder().decode([ChatSession].self, from: data) {
            sessions = list
        }
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let s = try? JSONDecoder().decode(AgentSettings.self, from: data) {
            settings = s
        }
        apiKey = UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
    }

    func saveSessions(_ list: [ChatSession]) {
        sessions = list
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: sessionsURL, options: .atomic)
        }
    }

    func saveSettings(_ s: AgentSettings) {
        settings = s
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    func saveAPIKey(_ key: String) {
        apiKey = key
        UserDefaults.standard.set(key, forKey: apiKeyKey)
    }
}

// ═════════════════════════════════════════════════════════════
// MARK: - 模型客户端（OpenAI 兼容，SSE 流式 + tool calling）
// ═════════════════════════════════════════════════════════════

final class LLMClient {

    enum ClientError: LocalizedError {
        case badURL(String)
        case missingKey
        case http(Int, String)
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .badURL(let s): return "接口地址不对：\(s)"
            case .missingKey: return "还没填 API Key（右上角 ⋯ → 设置）"
            case .http(let c, let b): return "服务端 \(c)：\(b.prefix(300))"
            case .badResponse(let s): return "响应异常：\(s)"
            }
        }
    }

    struct Turn {
        var text: String = ""
        var toolCalls: [ToolCall] = []
    }

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

    func stream(settings: AgentSettings,
                apiKey: String,
                messages: [ChatMessage],
                tools: [ToolSpec],
                onDelta: @escaping (String) -> Void) async throws -> Turn {

        guard !apiKey.isEmpty else { throw ClientError.missingKey }
        guard let url = Self.endpoint(settings.baseURL) else {
            throw ClientError.badURL(settings.baseURL)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(
            withJSONObject: Self.body(settings: settings, messages: messages, tools: tools))

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
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
                let i = tc.index ?? 0
                var e = buffer[i] ?? (id: "", name: "", args: "")
                if let id = tc.id, !id.isEmpty { e.id = id }
                if let n = tc.function?.name, !n.isEmpty { e.name += n }
                if let a = tc.function?.arguments { e.args += a }
                buffer[i] = e
            }
        }

        turn.toolCalls = buffer.keys.sorted().compactMap { i in
            guard let e = buffer[i], !e.name.isEmpty else { return nil }
            let id = e.id.isEmpty ? "call_\(UUID().uuidString.prefix(8))" : e.id
            return ToolCall(id: id, function: FunctionCall(name: e.name, arguments: e.args))
        }
        return turn
    }

    static func endpoint(_ base: String) -> URL? {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if !s.hasSuffix("/chat/completions") { s += "/chat/completions" }
        return URL(string: s)
    }

    static func body(settings: AgentSettings,
                     messages: [ChatMessage],
                     tools: [ToolSpec]) -> [String: Any] {
        var wire: [[String: Any]] = []
        for m in messages {
            switch m.role {
            case .assistant:
                var d: [String: Any] = ["role": "assistant"]
                d["content"] = m.content.isEmpty ? NSNull() : m.content
                if let calls = m.toolCalls, !calls.isEmpty {
                    d["tool_calls"] = calls.map {
                        ["id": $0.id, "type": "function",
                         "function": ["name": $0.function.name,
                                      "arguments": $0.function.arguments]] as [String: Any]
                    }
                }
                wire.append(d)
            case .tool:
                wire.append(["role": "tool",
                             "tool_call_id": m.toolCallID ?? "",
                             "content": m.content])
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
            body["tools"] = tools.map { (spec: ToolSpec) -> [String: Any] in
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

// ═════════════════════════════════════════════════════════════
// MARK: - 工具（全部 iOS 原生能力）
// ═════════════════════════════════════════════════════════════

final class ToolRegistry {

    private let docs: URL

    init(documents: URL) { self.docs = documents.standardizedFileURL }

    var specs: [ToolSpec] {
        [
            ToolSpec(name: "now",
                     description: "获取设备当前时间（含时区）。涉及“今天/明天/几点了”先调它。",
                     parameters: obj([:], required: [])),

            ToolSpec(name: "list_files",
                     description: "列出沙盒 Documents 目录下的文件。path 传空表示根目录。",
                     parameters: obj(["path": str("相对路径，可为空")], required: [])),

            ToolSpec(name: "read_file",
                     description: "读取沙盒内文本文件（最多 20000 字符）。",
                     parameters: obj(["path": str("相对 Documents 的路径")], required: ["path"])),

            ToolSpec(name: "write_file",
                     description: "把文本写入沙盒内文件，自动建目录并覆盖同名文件。",
                     parameters: obj(["path": str("相对 Documents 的路径"),
                                      "content": str("要写入的完整文本")],
                                     required: ["path", "content"])),

            ToolSpec(name: "http_get",
                     description: "GET 一个 http(s) 地址返回正文（最多 20000 字符）。查资料、调 API 用它。",
                     parameters: obj(["url": str("完整 URL"),
                                      "max_chars": num("返回上限，默认 20000")],
                                     required: ["url"])),

            ToolSpec(name: "clipboard_get",
                     description: "读取系统剪贴板文本。",
                     parameters: obj([:], required: [])),

            ToolSpec(name: "clipboard_set",
                     description: "把文本写进系统剪贴板，用户可直接粘贴到别处。",
                     parameters: obj(["text": str("要复制的内容")], required: ["text"])),

            ToolSpec(name: "open_url",
                     description: "用系统浏览器或对应 App 打开一个 URL。",
                     parameters: obj(["url": str("完整 URL")], required: ["url"])),

            ToolSpec(name: "notify",
                     description: "发一条本地通知到通知中心，适合提醒用户。",
                     parameters: obj(["title": str("标题"), "body": str("正文")],
                                     required: ["title", "body"])),
        ]
    }

    func run(name: String, argumentsJSON: String) async -> (String, Bool) {
        let json = argumentsJSON.isEmpty ? "{}" : argumentsJSON
        let args = (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]) ?? [:]

        do {
            switch name {
            case "now":
                let f = DateFormatter()
                f.locale = Locale(identifier: "zh_CN")
                f.dateFormat = "yyyy年M月d日 EEEE HH:mm:ss"
                return ("当前时间：\(f.string(from: Date()))（\(TimeZone.current.identifier)）", false)

            case "list_files":
                let dir = resolve(args["path"] as? String ?? "") ?? docs
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) else {
                    return ("路径不存在：\(rel(dir))", true)
                }
                let items = (try? FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey])) ?? []
                if items.isEmpty { return ("（空目录：\(rel(dir))）", false) }
                let lines = items.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { u -> String in
                    let v = try? u.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                    if v?.isDirectory == true { return "\(u.lastPathComponent)/" }
                    return "\(u.lastPathComponent)  \(v?.fileSize ?? 0) bytes"
                }
                return ("目录 \(rel(dir))：\n" + lines.joined(separator: "\n"), false)

            case "read_file":
                guard let url = resolve(args["path"] as? String ?? "") else {
                    return ("路径越界（只能读写 App 沙盒内文件）", true)
                }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                    return ("读不到：\(rel(url))", true)
                }
                return (String(text.prefix(20_000)), false)

            case "write_file":
                guard let url = resolve(args["path"] as? String ?? "") else {
                    return ("路径越界（只能读写 App 沙盒内文件）", true)
                }
                let content = args["content"] as? String ?? ""
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: url, atomically: true, encoding: .utf8)
                return ("已写入 \(rel(url))（\(content.utf8.count) 字节）", false)

            case "http_get":
                guard let raw = args["url"] as? String, let url = URL(string: raw) else {
                    return ("URL 不合法", true)
                }
                var req = URLRequest(url: url)
                req.timeoutInterval = 30
                req.setValue("PocketAgent/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
                let (data, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                let limit = (args["max_chars"] as? Int) ?? 20_000
                let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? "<二进制 \(data.count) 字节>"
                return ("HTTP \(code)\n" + String(text.prefix(limit)), false)

            case "clipboard_get":
                let text = await MainActor.run { UIPasteboard.general.string ?? "" }
                return (text.isEmpty ? "（剪贴板为空）" : text, false)

            case "clipboard_set":
                let text = args["text"] as? String ?? ""
                await MainActor.run { UIPasteboard.general.string = text }
                return ("已复制 \(text.count) 个字符到剪贴板", false)

            case "open_url":
                guard let raw = args["url"] as? String, let url = URL(string: raw) else {
                    return ("URL 不合法", true)
                }
                let ok = await MainActor.run { UIApplication.shared.canOpenURL(url) }
                guard ok else { return ("系统拒绝打开：\(raw)", true) }
                await MainActor.run { UIApplication.shared.open(url) }
                return ("已交给系统打开：\(raw)", false)

            case "notify":
                let title = args["title"] as? String ?? "PocketAgent"
                let body = args["body"] as? String ?? ""
                try await postNotification(title: title, body: body)
                return ("通知已发出", false)

            default:
                return ("没有这个工具：\(name)", true)
            }
        } catch {
            return ("工具执行失败：\(error.localizedDescription)", true)
        }
    }

    // 路径必须落在 Documents 内
    private func resolve(_ raw: String) -> URL? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: URL
        if t.isEmpty || t == "." || t == "/" {
            candidate = docs
        } else if t.hasPrefix("file://"), let u = URL(string: t) {
            candidate = u
        } else if t.hasPrefix("/") {
            candidate = URL(fileURLWithPath: t)
        } else {
            candidate = docs.appendingPathComponent(t)
        }
        let std = candidate.standardizedFileURL
        guard std.path == docs.path || std.path.hasPrefix(docs.path + "/") else { return nil }
        return std
    }

    private func rel(_ url: URL) -> String {
        let p = url.standardizedFileURL.path
        return p == docs.path ? "." : String(p.dropFirst(docs.path.count + 1))
    }

    private func obj(_ props: [String: Any], required: [String]) -> [String: Any] {
        ["type": "object", "properties": props, "required": required]
    }
    private func str(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
    private func num(_ d: String) -> [String: Any] { ["type": "integer", "description": d] }

    private func postNotification(title: String, body: String) async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        guard granted else { throw NSError(domain: "notify", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "没给通知权限"]) }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        try await center.add(UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

// ═════════════════════════════════════════════════════════════
// MARK: - Agent 主循环
// ═════════════════════════════════════════════════════════════

final class AgentRuntime: ObservableObject {

    @Published var sessions: [ChatSession] = []
    @Published var current: ChatSession
    @Published var isRunning = false
    @Published var statusLine: String = ""
    @Published var errorText: String?

    private let client = LLMClient()
    private let tools: ToolRegistry
    private let store = Store.shared
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var runTask: Task<Void, Never>?
    private let historyLimit = 60

    init() {
        let s = Store.shared
        s.load()
        tools = ToolRegistry(documents: s.documentsDirectory)
        sessions = s.sessions
        current = s.sessions.first ?? ChatSession()
        if sessions.isEmpty { sessions = [current] }
    }

    func start(_ text: String) {
        guard runTask == nil else { return }
        runTask = Task { [weak self] in
            await self?.run(text)
            self?.runTask = nil
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
        statusLine = ""
    }

    private func run(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        errorText = nil
        isRunning = true
        beginBackgroundWork()
        defer {
            isRunning = false
            statusLine = ""
            endBackgroundWork()
            persist()
        }

        current.messages.append(.user(trimmed))
        if current.title == "新对话" { current.title = String(trimmed.prefix(18)) }

        let settings = store.settings
        let apiKey = store.apiKey
        guard !apiKey.isEmpty else {
            errorText = "还没填 API Key：右上角 ⋯ → 设置"
            return
        }

        for round in 1...max(1, settings.maxRounds) {
            if Task.isCancelled { return }
            statusLine = round == 1 ? "思考中…" : "第 \(round) 轮推理…"

            let payload = trimmedHistory(current.messages)

            var placeholder = ChatMessage.assistant("")
            placeholder.id = UUID().uuidString
            current.messages.append(placeholder)
            let idx = current.messages.count - 1

            let turn: LLMClient.Turn
            do {
                turn = try await client.stream(
                    settings: settings,
                    apiKey: apiKey,
                    messages: payload,
                    tools: tools.specs,
                    onDelta: { [weak self] piece in
                        guard let self, self.current.messages.indices.contains(idx) else { return }
                        self.current.messages[idx].content += piece
                    })
            } catch {
                if current.messages.indices.contains(idx) { current.messages.remove(at: idx) }
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
                errorText = error.localizedDescription
                return
            }

            guard current.messages.indices.contains(idx) else { return }
            current.messages[idx].content = turn.text
            current.messages[idx].toolCalls = turn.toolCalls.isEmpty ? nil : turn.toolCalls

            if turn.toolCalls.isEmpty {
                if turn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    current.messages[idx].content = "（模型返回了空内容）"
                }
                return
            }

            for call in turn.toolCalls {
                if Task.isCancelled { return }
                statusLine = "运行 \(call.function.name)…"
                let (content, isError) = await tools.run(
                    name: call.function.name, argumentsJSON: call.function.arguments)
                current.messages.append(
                    .tool(isError ? "【错误】" + content : content,
                          id: call.id, name: call.function.name))
            }
        }

        current.messages.append(
            .assistant("（已达单轮工具调用上限 \(store.settings.maxRounds) 轮，先停在这里。）"))
    }

    // MARK: 会话
    func newSession() {
        stop()
        let fresh = ChatSession()
        current = fresh
        sessions.insert(fresh, at: 0)
        persist()
    }

    func open(_ s: ChatSession) {
        stop()
        current = s
    }

    func delete(_ s: ChatSession) {
        sessions.removeAll { $0.id == s.id }
        if current.id == s.id {
            current = sessions.first ?? ChatSession()
            if sessions.isEmpty { sessions = [current] }
        }
        persist()
    }

    private func trimmedHistory(_ messages: [ChatMessage]) -> [ChatMessage] {
        var body = messages.filter { $0.role != .system }
        if body.count > historyLimit { body = Array(body.suffix(historyLimit)) }
        return [.system(store.settings.systemPrompt)] + body
    }

    private func persist() {
        current.updatedAt = Date()
        if let i = sessions.firstIndex(where: { $0.id == current.id }) {
            sessions[i] = current
        } else {
            sessions.insert(current, at: 0)
        }
        sessions.sort { $0.updatedAt > $1.updatedAt }
        store.saveSessions(sessions)
    }

    private func beginBackgroundWork() {
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "agent-turn") { [weak self] in
            self?.endBackgroundWork()
        }
    }

    private func endBackgroundWork() {
        guard bgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }
}

// ═════════════════════════════════════════════════════════════
// MARK: - 界面
// ═════════════════════════════════════════════════════════════

struct ContentView: View {
    @StateObject private var rt = AgentRuntime()
    @State private var draft = ""
    @State private var showSettings = false
    @State private var showSessions = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcript
                if !rt.statusLine.isEmpty { statusBar }
                if let err = rt.errorText { errorBanner(err) }
                inputBar
            }
            .navigationTitle(rt.current.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showSessions = true } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { rt.newSession() } label: {
                            Label("新对话", systemImage: "square.and.pencil")
                        }
                        Button { showSettings = true } label: {
                            Label("设置", systemImage: "gearshape")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsSheet() }
            .sheet(isPresented: $showSessions) { SessionsSheet(runtime: rt) }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(rt.current.messages.filter { $0.role != .system }) { msg in
                        MessageRow(message: msg).id(msg.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .onChange(of: rt.current.messages.count) { _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7)
            Text(rt.statusLine).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.yellow.opacity(0.12))
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { rt.errorText = nil } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("让它干点什么…", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 20))
                .focused($focused)
                .disabled(rt.isRunning)

            if rt.isRunning {
                Button { rt.stop() } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 30)).foregroundStyle(.red)
                }
            } else {
                Button { submit() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty
                                         ? Color.gray : Color.blue)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func submit() {
        let text = draft
        draft = ""
        focused = false
        rt.start(text)
    }
}

struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.content)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.blue.opacity(0.92),
                                in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
            }

        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                if !message.content.isEmpty {
                    MarkdownLite(text: message.content)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color(uiColor: .secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 16))
                        .textSelection(.enabled)
                }
                if let calls = message.toolCalls, !calls.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "hammer.fill").font(.caption2)
                        Text(calls.map { $0.function.name }.joined(separator: " · "))
                            .font(.caption2.monospaced())
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.purple.opacity(0.15), in: Capsule())
                    .foregroundStyle(.purple)
                }
                Spacer(minLength: 0)
            }

        case .tool:
            ToolRow(message: message)

        case .system:
            EmptyView()
        }
    }
}

struct ToolRow: View {
    let message: ChatMessage

    var body: some View {
        DisclosureGroup {
            Text(message.content)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver.fill").font(.caption2)
                Text("\(message.toolName ?? "tool") 返回").font(.caption2.monospaced())
                Text(String(message.content.prefix(36)))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(uiColor: .tertiarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12))
        .accentColor(.gray)
    }
}

/// 只处理 ``` 代码块，够读就行
struct MarkdownLite: View {
    let text: String

    var body: some View {
        let parts = text.components(separatedBy: "```")
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                if i % 2 == 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(part.trimmingCharacters(in: .newlines))
                            .font(.caption.monospaced())
                            .padding(10)
                            .textSelection(.enabled)
                    }
                    .background(Color.black.opacity(0.85),
                                in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.green)
                } else if !part.isEmpty {
                    Text(part)
                }
            }
        }
    }
}

// ═════════════════════════════════════════════════════════════
// MARK: - 设置 / 会话
// ═════════════════════════════════════════════════════════════

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var baseURL = Store.shared.settings.baseURL
    @State private var model = Store.shared.settings.model
    @State private var apiKey = Store.shared.apiKey
    @State private var systemPrompt = Store.shared.settings.systemPrompt
    @State private var temperature = Store.shared.settings.temperature
    @State private var maxRounds = Store.shared.settings.maxRounds

    @State private var testing = false
    @State private var testResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://api.deepseek.com", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.callout.monospaced())
                    TextField("deepseek-chat", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                    TextField("sk-…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                } header: {
                    Text("模型服务（OpenAI 兼容）")
                } footer: {
                    Text("baseURL 填到 /v1 或根路径都行，App 自己拼 /chat/completions。")
                }

                Section("行为") {
                    HStack {
                        Text("温度")
                        Slider(value: $temperature, in: 0...1.5, step: 0.1)
                        Text(String(format: "%.1f", temperature))
                            .font(.caption.monospaced())
                    }
                    Stepper("工具轮数上限：\(maxRounds)", value: $maxRounds, in: 1...20)
                }

                Section("系统提示词（人设）") {
                    TextEditor(text: $systemPrompt)
                        .font(.callout)
                        .frame(minHeight: 150)
                }

                Section {
                    Button {
                        Task { await test() }
                    } label: {
                        HStack {
                            Text("测试连接")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(testing || apiKey.isEmpty)

                    if let r = testResult {
                        Text(r).font(.caption)
                            .foregroundStyle(r.hasPrefix("✅") ? Color.green : Color.red)
                    }
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save(); dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        var s = Store.shared.settings
        s.baseURL = baseURL
        s.model = model
        s.systemPrompt = systemPrompt
        s.temperature = temperature
        s.maxRounds = maxRounds
        Store.shared.saveSettings(s)
        Store.shared.saveAPIKey(apiKey)
    }

    private func test() async {
        testing = true
        testResult = nil
        defer { testing = false }

        var s = Store.shared.settings
        s.baseURL = baseURL
        s.model = model

        do {
            let turn = try await LLMClient().stream(
                settings: s, apiKey: apiKey,
                messages: [.user("只回复两个字：可用")],
                tools: [], onDelta: { _ in })
            testResult = "✅ 通了：「\(turn.text.trimmingCharacters(in: .whitespaces).prefix(30))」"
        } catch {
            testResult = "❌ \(error.localizedDescription)"
        }
    }
}

struct SessionsSheet: View {
    @ObservedObject var runtime: AgentRuntime
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(runtime.sessions) { s in
                    Button {
                        runtime.open(s)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.title).font(.callout).lineLimit(1)
                            Text("\(s.messages.count) 条 · \(s.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            runtime.delete(s)
                        } label: { Label("删除", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle("会话")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        runtime.newSession()
                        dismiss()
                    } label: { Image(systemName: "plus") }
                }
            }
        }
    }
}
