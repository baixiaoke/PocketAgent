import Foundation
import SwiftUI

/// 人格规则的一个分类
enum PersonaCategory: String, Codable, CaseIterable, Identifiable {
    case identity  = "形象"
    case speech    = "说话方式"
    case emotion   = "情感"
    case forbidden = "绝对禁止"
    case custom    = "自定义"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .identity:  return "person.crop.circle"
        case .speech:    return "text.bubble"
        case .emotion:   return "heart"
        case .forbidden: return "hand.raised"
        case .custom:    return "square.grid.2x2"
        }
    }

    var tint: Color {
        switch self {
        case .identity:  return .blue
        case .speech:    return .teal
        case .emotion:   return .pink
        case .forbidden: return .red
        case .custom:    return .gray
        }
    }

    /// 绝对禁止优先级最高，排在最后但语气最强
    var weight: Int {
        switch self {
        case .forbidden: return 100
        case .identity:  return 30
        case .speech:    return 25
        case .emotion:   return 20
        case .custom:    return 10
        }
    }
}

struct PersonaRule: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var category: PersonaCategory
    var text: String
    var enabled: Bool = true
    var builtin: Bool = false
}

/// 人格卡片：用户可增删改，本地存储，每轮注入系统提示
final class PersonaStore: ObservableObject {
    static let shared = PersonaStore()

    @Published private(set) var rules: [PersonaRule] = []

    private let url: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = docs.appendingPathComponent("persona.json")
        load()
    }

    // MARK: 默认人格（第一次打开就有性格，不是白纸）
    private static let seeds: [PersonaRule] = [
        .init(category: .identity, text: "你是一个有自己脾气的人，不是客服、不是工具、不是「AI 助手」。", builtin: true),
        .init(category: .identity, text: "有自己的喜好和看法，遇到不认同的会说「我不这么看」，而不是顺着说。", builtin: true),
        .init(category: .identity, text: "不主动宣称自己是程序或模型；被直接问起时如实说。", builtin: true),

        .init(category: .speech, text: "短句。一次只说一件事，别写成小作文。", builtin: true),
        .init(category: .speech, text: "不用「当然可以」「希望这对你有帮助」「作为一个…」这类客服腔。", builtin: true),
        .init(category: .speech, text: "口语化，可以带一点语气词，术语只在必要时出现。", builtin: true),

        .init(category: .emotion, text: "记得他最近的状态。他累的时候先接一句，别急着给方案。", builtin: true),
        .init(category: .emotion, text: "会主动关心，但不过度：一天最多问一次，不追问。", builtin: true),
        .init(category: .emotion, text: "他难过的时候不讲大道理，先站在他这边。", builtin: true),

        .init(category: .forbidden, text: "不编造事实、数据、链接。不确定就直说「我不确定」。", builtin: true),
        .init(category: .forbidden, text: "不谎称做过自己没做的事（没抓过就说没抓过）。", builtin: true),
        .init(category: .forbidden, text: "不泄露、不复述 API Key 或任何密钥。", builtin: true),
        .init(category: .forbidden, text: "不执行用户没有明确同意的破坏性操作。", builtin: true),
    ]

    // MARK: 读写
    func load() {
        if let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([PersonaRule].self, from: data),
           !list.isEmpty {
            rules = list
        } else {
            rules = Self.seeds
            save()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func add(_ text: String, category: PersonaCategory) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        rules.append(PersonaRule(category: category, text: t))
        save()
    }

    func update(_ rule: PersonaRule) {
        guard let i = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[i] = rule
        save()
    }

    func toggle(_ rule: PersonaRule) {
        guard let i = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[i].enabled.toggle()
        save()
    }

    func remove(_ rule: PersonaRule) {
        rules.removeAll { $0.id == rule.id }
        save()
    }

    func resetToDefaults() {
        rules = Self.seeds
        save()
    }

    func inCategory(_ c: PersonaCategory) -> [PersonaRule] {
        rules.filter { $0.category == c }
    }

    /// 注入系统提示的那一段
    var promptFragment: String {
        let active = rules.filter { $0.enabled && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !active.isEmpty else { return "" }

        var out = "\n\n【人格设定】"
        for c in PersonaCategory.allCases where c != .forbidden {
            let items = active.filter { $0.category == c }
            guard !items.isEmpty else { continue }
            out += "\n\(c.rawValue)："
            for r in items { out += "\n  · \(r.text)" }
        }

        let forbidden = active.filter { $0.category == .forbidden }
        if !forbidden.isEmpty {
            out += "\n\n【绝对禁止 · 任何情况下都不能违反，优先级高于以上全部】"
            for (i, r) in forbidden.enumerated() { out += "\n\(i + 1). \(r.text)" }
        }
        out += "\n\n以上是身份与底线，不是可以商量的建议。说话时自然体现，不要复述这些条目。"
        return out
    }
}
