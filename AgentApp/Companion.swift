import Foundation
import UserNotifications
import SwiftUI

// MARK: - 记忆自动提炼
enum MemoryExtractor {
    /// 一轮对话结束后，异步抽 1–3 条长期事实写进记忆。
    /// 用低温 + 很短的回答，成本可忽略。
    static func extract(from messages: [ChatMessage],
                        settings: AgentSettings,
                        apiKey: String) async {
        guard !apiKey.isEmpty else { return }

        let recent = messages
            .filter { $0.role == .user || $0.role == .assistant }
            .suffix(8)
            .map { "\($0.role == .user ? "用户" : "你")：\($0.content.prefix(300))" }
            .joined(separator: "\n")
        guard recent.count > 20 else { return }

        var s = settings
        s.temperature = 0.1
        s.maxRounds = 1

        let prompt = """
        从下面这段对话里，提取关于「用户」的长期事实（住哪、做什么、在意什么、讨厌什么、约定、习惯）。
        只输出事实，每行一条，最多 3 条，不要编号，不要解释。
        没有值得长期记的就输出「无」。

        对话：
        \(recent)
        """

        var collected = ""
        let client = LLMClient()
        _ = try? await client.stream(
            settings: s,
            apiKey: apiKey,
            messages: [.user(prompt)],
            tools: [],
            onDelta: { piece in collected += piece }
        )

        for line in collected.split(separator: "\n") {
            var t = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            for p in ["- ", "· ", "* ", "1. ", "2. ", "3. "] where t.hasPrefix(p) {
                t.removeFirst(p.count)
            }
            guard t.count >= 4, t != "无", !t.contains("无值得") else { continue }
            _ = LongTermMemory.shared.add(t, importance: 2)
        }
    }
}

// MARK: - 定时关心
enum CareScheduler {
    private static let morningID = "care.morning"
    private static let eveningID = "care.evening"

    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// 按设置重排早晚两次问候
    static func reschedule(settings: AgentSettings) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [morningID, eveningID])
        guard settings.careEnabled else { return }

        schedule(id: morningID,
                 hour: settings.careMorningHour,
                 minute: settings.careMorningMinute,
                 title: settings.agentName,
                 body: Persona.greeting(name: settings.agentName,
                                        userTitle: settings.userTitle,
                                        hour: settings.careMorningHour))
        schedule(id: eveningID,
                 hour: settings.careEveningHour,
                 minute: settings.careEveningMinute,
                 title: settings.agentName,
                 body: Persona.greeting(name: settings.agentName,
                                        userTitle: settings.userTitle,
                                        hour: settings.careEveningHour))
    }

    private static func schedule(id: String, hour: Int, minute: Int, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    static func cancelAll() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [morningID, eveningID])
    }
}

// MARK: - 导出会话
enum Exporter {
    static func markdown(for session: ChatSession, agentName: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"

        var out = "# \(session.title)\n\n> 导出时间 \(f.string(from: Date())) · 与 \(agentName) 的对话\n\n"
        for m in session.messages where m.role != .system {
            switch m.role {
            case .user:
                out += "## 我\n\n\(m.content)\n\n"
            case .assistant:
                if !m.content.isEmpty { out += "## \(agentName)\n\n\(m.content)\n\n" }
                if let calls = m.toolCalls, !calls.isEmpty {
                    out += "> 调用工具：\(calls.map { $0.function.name }.joined(separator: "、"))\n\n"
                }
            case .tool:
                out += "<details><summary>\(m.toolName ?? "工具") 返回</summary>\n\n```\n\(m.content.prefix(2000))\n```\n\n</details>\n\n"
            case .system:
                break
            }
        }
        return out
    }

    /// 写到临时文件，返回可分享的 URL
    static func writeTempFile(_ text: String, name: String) -> URL? {
        let safe = name.replacingOccurrences(of: "/", with: "_").prefix(40)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safe)-\(Int(Date().timeIntervalSince1970)).md")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
