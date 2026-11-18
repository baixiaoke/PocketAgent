import Foundation
import Security

/// 极简 Keychain 封装，只存 API Key。
enum Keychain {
    private static let service = "ai.pocketagent.app"

    static func set(_ value: String, for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
}

/// 会话 + 配置的本地持久化（全在 App 沙盒里，不联网）
final class Store {
    static let shared = Store()

    private let docs: URL
    private let sessionsURL: URL
    private let settingsKey = "agent.settings"

    private(set) var sessions: [ChatSession] = []
    private(set) var settings = AgentSettings()
    private(set) var apiKey: String = ""

    private init() {
        docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        sessionsURL = docs.appendingPathComponent("sessions.json")
        load()
    }

    var documentsDirectory: URL { docs }

    func load() {
        if let data = try? Data(contentsOf: sessionsURL),
           let list = try? JSONDecoder().decode([ChatSession].self, from: data) {
            sessions = list
        }
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let s = try? JSONDecoder().decode(AgentSettings.self, from: data) {
            settings = s
        }
        apiKey = Keychain.get("apiKey")

        // 品牌迁移：旧默认名「小椒」→ 新名「青露」
        if settings.agentName == "小椒" {
            settings.agentName = "青露"
            saveSettings(settings)
        }

        // 系统提示词废弃：把用户写过的内容转成一条「自定义」人格规则，避免丢失
        let legacy = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !legacy.isEmpty {
            PersonaStore.shared.add(legacy, category: .custom)
            settings.systemPrompt = ""
            saveSettings(settings)
        }
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
        Keychain.set(key, for: "apiKey")
    }
}
