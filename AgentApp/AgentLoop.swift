import Foundation
import SwiftUI
import UIKit

/// agent 主循环：模型 → tool_calls → 执行工具 → 回灌结果 → 再问模型，直到它不再调工具。
@MainActor
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

    /// 送进模型的历史上限（条），防止上下文无限膨胀
    private let historyLimit = 60

    init() {
        let s = Store.shared
        s.load()
        tools = ToolRegistry(documents: s.documentsDirectory)
        let list = s.sessions
        sessions = list
        current = list.first ?? ChatSession()
        if list.isEmpty { sessions = [current] }
    }

    // MARK: - 对外入口
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

    // MARK: - 主循环
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

        for round in 1...max(1, settings.maxRounds) {
            if Task.isCancelled { return }
            statusLine = round == 1 ? "思考中…" : "第 \(round) 轮推理…"

            // 先算要发的历史（此时还没插空 assistant，避免发出空内容被拒）
            if store.apiKey.isEmpty {
                errorText = LLMClient.ClientError.missingKey.localizedDescription
                return
            }
            let payload = trimmedHistory(current.messages)

            // 插一条空 assistant，流式往里写
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
                        Task { @MainActor in
                            guard let self, self.current.messages.indices.contains(idx) else { return }
                            self.current.messages[idx].content += piece
                        }
                    }
                )
            } catch {
                if current.messages.indices.contains(idx) { current.messages.remove(at: idx) }
                // 主动停止：URLSession 抛的是 URLError.cancelled，不是 CancellationError
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

            // 逐个执行工具
            for call in turn.toolCalls {
                if Task.isCancelled { return }
                statusLine = "运行 \(call.function.name)…"
                let (content, isError) = await tools.run(
                    name: call.function.name,
                    argumentsJSON: call.function.arguments
                )
                let body = isError ? "【错误】" + content : content
                current.messages.append(.tool(body, id: call.id, name: call.function.name))
            }
        }

        current.messages.append(
            .assistant("（已达单轮工具调用上限 \(store.settings.maxRounds) 轮，先停在这里。）")
        )
    }

    // MARK: - 会话管理
    func newSession() {
        stop()
        let fresh = ChatSession()
        current = fresh
        sessions.insert(fresh, at: 0)
        persist()
    }

    func open(_ session: ChatSession) {
        stop()
        current = session
    }

    func delete(_ session: ChatSession) {
        sessions.removeAll { $0.id == session.id }
        if current.id == session.id {
            current = sessions.first ?? ChatSession()
            if sessions.isEmpty { sessions = [current] }
        }
        persist()
    }

    /// 系统提示词每次现拼，不进会话存储
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

    // MARK: - 后台续命：锁屏后还能再跑几分钟（iOS 给的上限），够收尾一个工具轮
    private func beginBackgroundWork() {
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "agent-turn") { [weak self] in
            Task { @MainActor in self?.endBackgroundWork() }
        }
    }

    private func endBackgroundWork() {
        guard bgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }
}
