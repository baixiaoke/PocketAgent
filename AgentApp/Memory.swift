import Foundation
import SwiftUI

struct MemoryItem: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var text: String
    var createdAt: Date = Date()
    var importance: Int = 1          // 1 普通 / 2 重要 / 3 别忘

    var when: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f.string(from: createdAt)
    }
}

/// 长期记忆：本地 JSON，永久保留；每轮对话都会挑一部分注入系统提示。
final class LongTermMemory: ObservableObject {
    static let shared = LongTermMemory()

    @Published private(set) var items: [MemoryItem] = []

    private let url: URL
    private let limit = 24            // 每轮最多注入多少条

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = docs.appendingPathComponent("memory.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([MemoryItem].self, from: data) else { return }
        items = list
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// 返回 false 表示重复，没记
    @discardableResult
    func add(_ text: String, importance: Int = 1) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { return false }
        if items.contains(where: { $0.text == t }) { return false }
        items.insert(MemoryItem(text: t, importance: max(1, min(3, importance))), at: 0)
        if items.count > 300 { items = Array(items.prefix(300)) }
        save()
        return true
    }

    func remove(_ id: String) {
        items.removeAll { $0.id == id }
        save()
    }

    func clear() {
        items = []
        save()
    }

    /// 简单关键词命中，够用；不引入向量检索
    func search(_ query: String) -> [MemoryItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(items.prefix(20)) }
        let chars = Array(q)
        return items.filter { item in
            if item.text.contains(q) { return true }
            // 允许部分匹配：问题里的任意 2 字片段命中就算
            guard chars.count >= 2 else { return false }
            for i in 0..<(chars.count - 1) {
                let frag = String(chars[i...i + 1])
                if item.text.contains(frag) { return true }
            }
            return false
        }.prefix(20).map { $0 }
    }

    /// 注入系统提示的那一段
    var promptFragment: String {
        guard !items.isEmpty else { return "" }
        let chosen = items
            .sorted { ($0.importance, $0.createdAt) > ($1.importance, $1.createdAt) }
            .prefix(limit)
        let lines = chosen.map { "- \($0.text)（\($0.when)）" }
        return "\n\n【你记得的事】\n" + lines.joined(separator: "\n")
    }
}

/// 情感陪伴：人设 + 时段问候
enum Persona {

    static func greeting(name: String, userTitle: String, hour: Int = Calendar.current.component(.hour, from: Date())) -> String {
        switch hour {
        case 5..<9:   return "早，\(userTitle)。今天想先干哪件？"
        case 9..<12:  return "上午好，\(userTitle)。"
        case 12..<14: return "中午了，吃了吗？"
        case 14..<18: return "下午好，\(userTitle)。"
        case 18..<22: return "晚上好，\(userTitle)。今天还顺利吗？"
        default:      return "这么晚还没睡？我在。"
        }
    }

    static func toneLine(_ tone: String) -> String {
        switch tone {
        case "温柔": return "说话温和、有耐心，先接住情绪再给建议。"
        case "俏皮": return "语气轻快，偶尔开玩笑，但正事上不含糊。"
        case "直接": return "不绕弯子，先给结论，必要时才解释。"
        default:     return "自然、像朋友一样说话。"
        }
    }
}
