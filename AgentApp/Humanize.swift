import Foundation
import SwiftUI

/// 让 agent 像有作息、会主动开口的人
enum Humanize {

    /// 深夜判定（23:00–06:00）
    static func isLateNight(_ date: Date = Date()) -> Bool {
        let h = Calendar.current.component(.hour, from: date)
        return h >= 23 || h < 6
    }

    static func hour(_ date: Date = Date()) -> Int {
        Calendar.current.component(.hour, from: date)
    }

    /// 主动开口的一句话（不花 token，用模板 + 时间 + 记忆）
    static func proactiveLine(name: String, hour: Int, memoryHint: String?) -> String {
        let pool: [String]
        switch hour {
        case 6..<11:
            pool = ["早", "醒了？", "今天起这么早", "早啊 吃了吗"]
        case 11..<14:
            pool = ["中午吃点啥", "在忙吗", "记得吃饭"]
        case 14..<18:
            pool = ["在干嘛", "忙完了没", "下午有点犯困"]
        case 18..<22:
            pool = ["回来了吗", "今天怎么样", "晚上有安排吗"]
        case 22..<24:
            pool = ["还没睡？", "该睡了", "今天累不累"]
        default:
            pool = ["这么晚还没睡", "睡不着？", "早点休息吧"]
        }
        var line = pool.randomElement() ?? "在吗"
        if let hint = memoryHint, !hint.isEmpty, Bool.random() {
            line = "上次说的那件事，后来怎么样了"
        }
        return line
    }

    /// 「你怎么才回」这类被冷落的话
    static func neglectedLine(gapHours: Double) -> String {
        if gapHours >= 12 { return "好久没见你说话了" }
        if gapHours >= 3 { return "你去哪了" }
        return "在忙？"
    }

    /// 作息对说话的影响
    static func scheduleHint(hour: Int) -> String {
        // 大肥鱼这套人设是夜猫子：越晚越精神，和别人相反
        if UserDefaults.standard.string(forKey: "pa.personaPreset") == "dafeiyu" {
            if hour >= 23 || hour < 6 {
                return "现在是深夜，但你越晚越精神，一点也不困，聊得动；不会主动拿「我困了」当收尾，主人不喊停你就接着聊。"
            }
            if hour >= 6 && hour < 10 {
                return "现在是早上，你刚睡没多久就醒了，有点起床气，句子短。"
            }
            return ""
        }

        if hour >= 23 || hour < 6 {
            return "现在是深夜。你有点困了，回复更短、更慢，偶尔会说要睡了，但愿意陪他再说两句。"
        }
        if hour < 9 {
            return "现在是早上。你刚醒，回复短而随意，可以带点没睡醒的感觉。"
        }
        if hour >= 12 && hour < 14 {
            return "现在是中午。你在吃饭或刚吃完，语气松。"
        }
        if hour >= 22 {
            return "已经很晚了。你开始犯困，句子更短。"
        }
        return ""
    }
}

/// 记忆「上次互动时间」，用于主动开口 / 被冷落判断
final class Presence: ObservableObject {
    static let shared = Presence()

    private let lastUserKey = "pa.lastUserMessageAt"
    private let proactiveKey = "pa.lastProactiveAt"

    @Published private(set) var lastUserAt: Date
    @Published private(set) var lastProactiveAt: Date

    private init() {
        lastUserAt = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: lastUserKey))
        lastProactiveAt = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: proactiveKey))
        if lastUserAt.timeIntervalSince1970 == 0 { lastUserAt = Date.distantPast }
        if lastProactiveAt.timeIntervalSince1970 == 0 { lastProactiveAt = Date.distantPast }
    }

    func markUserMessage() {
        lastUserAt = Date()
        UserDefaults.standard.set(lastUserAt.timeIntervalSince1970, forKey: lastUserKey)
    }

    func markProactive() {
        lastProactiveAt = Date()
        UserDefaults.standard.set(lastProactiveAt.timeIntervalSince1970, forKey: proactiveKey)
    }

    /// 距上次用户说话多久（小时）
    var idleHours: Double {
        max(0, Date().timeIntervalSince(lastUserAt) / 3600)
    }

    /// 今天是否已经主动开口过
    var proactiveToday: Bool {
        Calendar.current.isDateInToday(lastProactiveAt)
    }
}
