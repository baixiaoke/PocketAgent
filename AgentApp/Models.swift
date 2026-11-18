import Foundation

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
    /// 只用于 UI 展示，不进请求体
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

/// 会话（一次对话的完整消息栈）
struct ChatSession: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var title: String = "新对话"
    var messages: [ChatMessage] = []
    var updatedAt: Date = Date()
}

/// 模型与服务配置
struct AgentSettings: Codable, Equatable {
    var baseURL: String = "https://api.deepseek.com"
    var model: String = "deepseek-chat"
    var systemPrompt: String = """
    你是运行在这台 iPhone 上的独立 agent，名字叫「小椒」。
    你能直接操作这台设备的原生能力：读写 App 沙盒里的文件、抓网页、剪贴板、打开链接、发通知、建提醒事项。
    规则：
    1. 需要事实或最新信息时用 http_get，不要凭记忆编。
    2. 需要落盘的内容用 write_file，别只在回复里说。
    3. 一次只调一个工具，拿到结果再决定下一步。
    4. 回答用简体中文，直接给结论，不要客套。
    """
    var maxRounds: Int = 8
    var temperature: Double = 0.7
}
