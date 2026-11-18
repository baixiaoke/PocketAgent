import Foundation
import SwiftUI

// MARK: - 情绪状态
struct MoodState: Codable, Equatable {
    var label: String = "平静"
    var valence: Double = 0.6      // 0 低落 … 1 愉快
    var energy: Double = 0.5       // 0 疲惫 … 1 兴奋
    var note: String = ""          // 一句话说明，给模型看
    var updatedAt: Date = Date()

    var emoji: String {
        if valence < 0.35 { return energy < 0.4 ? "🥺" : "😞" }
        if valence > 0.75 { return energy > 0.65 ? "🤩" : "😊" }
        if energy < 0.3 { return "😪" }
        if energy > 0.8 { return "⚡️" }
        return "🙂"
    }

    var tint: Color {
        if valence < 0.35 { return Color(red: 0.45, green: 0.55, blue: 0.95) }   // 蓝
        if valence > 0.75 { return Color(red: 1.0, green: 0.72, blue: 0.30) }     // 橙
        return Theme.cyan
    }

    /// 给系统提示用的一段
    var promptLine: String {
        var s = "\(label)（愉快 \(Int(valence * 100))% · 精力 \(Int(energy * 100))%）"
        if !note.isEmpty { s += "：\(note)" }
        return s
    }

    /// 语音风格：把情绪翻译成 TTS 的 style 指令
    /// 语音风格：只描述语速与表达，**不描述音色**（否则会变成另一个人）
    var voiceStyle: String {
        var parts: [String] = []
        if valence < 0.35 {
            parts.append("语速稍慢，语气平和")
        } else if valence > 0.75 {
            parts.append("语速稍快，语气轻快")
        }
        if energy < 0.3 {
            parts.append("句与句之间多停顿")
        } else if energy > 0.8 {
            parts.append("节奏紧一点")
        }
        return parts.joined(separator: "，")
    }
    /// 行为倾向：把数值翻译成说话方式
    var behavior: String {
        var lines: [String] = []
        if valence < 0.35 {
            lines.append("你现在兴致不高，话更少、更轻，多陪着，少讲道理。")
        } else if valence > 0.75 {
            lines.append("你现在心情不错，语气会往上走，愿意多说两句。")
        }
        if energy < 0.3 {
            lines.append("有点累，句子更短，少用感叹号。")
        } else if energy > 0.8 {
            lines.append("挺有精神，可以主动抛话题。")
        }
        if lines.isEmpty { lines.append("保持平稳，别用力过猛。") }
        return lines.joined(separator: " ")
    }
}

// MARK: - 存储
final class MoodStore: ObservableObject {
    static let shared = MoodStore()

    @Published private(set) var current: MoodState

    private let url: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = docs.appendingPathComponent("mood.json")
        if let data = try? Data(contentsOf: url),
           let m = try? JSONDecoder().decode(MoodState.self, from: data) {
            current = m
        } else {
            current = MoodState()
        }
    }

    func update(_ m: MoodState) {
        current = m
        if let data = try? JSONEncoder().encode(m) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// 手动微调（设置页用）
    func adjust(valence: Double? = nil, energy: Double? = nil, label: String? = nil) {
        var m = current
        if let v = valence { m.valence = max(0, min(1, v)) }
        if let e = energy { m.energy = max(0, min(1, e)) }
        if let l = label { m.label = l }
        m.updatedAt = Date()
        update(m)
    }
}

// MARK: - 分析
enum MoodAnalyzer {

    /// 节流：距上次更新不到 90 秒就跳过
    static func maybeAnalyze(messages: [ChatMessage],
                             settings: AgentSettings,
                             apiKey: String) async {
        guard !apiKey.isEmpty else { return }
        if Date().timeIntervalSince(MoodStore.shared.current.updatedAt) < 90 { return }
        await analyze(messages: messages, settings: settings, apiKey: apiKey)
    }

    static func analyze(messages: [ChatMessage],
                        settings: AgentSettings,
                        apiKey: String) async {
        let recent = messages
            .filter { $0.role == .user || $0.role == .assistant }
            .suffix(6)
            .map { "\($0.role == .user ? "用户" : "你")：\($0.content.prefix(200))" }
            .joined(separator: "\n")
        guard recent.count > 10 else { return }

        var s = settings
        s.temperature = 0.1

        let prompt = """
        读下面这段对话，判断「你」此刻的整体情绪状态，只输出一行 JSON，不要解释：
        {"label":"两个字的心情","valence":0到1的小数,"energy":0到1的小数,"note":"十字内的原因"}

        说明：valence 越低越低落，energy 越低越疲惫。
        对话：
        \(recent)
        """

        var out = ""
        _ = try? await LLMClient().stream(settings: s, apiKey: apiKey,
                                          messages: [.user(prompt)], tools: [],
                                          onDelta: { out += $0 })

        if let parsed = parse(out) {
            MoodStore.shared.update(parsed)
        } else {
            // 兜底：本地关键词粗判，不至于一直停在「平静」
            let guess = heuristics(recent)
            MoodStore.shared.update(guess)
        }
    }

    private static func parse(_ text: String) -> MoodState? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        var m = MoodState()
        m.label = (obj["label"] as? String) ?? "平静"
        if let v = obj["valence"] as? Double { m.valence = max(0, min(1, v)) }
        if let v = obj["valence"] as? Int { m.valence = max(0, min(1, Double(v))) }
        if let e = obj["energy"] as? Double { m.energy = max(0, min(1, e)) }
        if let e = obj["energy"] as? Int { m.energy = max(0, min(1, Double(e))) }
        m.note = (obj["note"] as? String) ?? ""
        m.updatedAt = Date()
        return m
    }

    private static func heuristics(_ text: String) -> MoodState {
        var m = MoodState()
        let low = ["累", "烦", "难受", "难过", "哭", "崩溃", "压力", "不想", "算了", "没意思"]
        let high = ["开心", "好耶", "哈哈", "爽", "太好了", "谢谢", "喜欢", "棒", "厉害"]
        let l = low.filter { text.contains($0) }.count
        let h = high.filter { text.contains($0) }.count

        if l > h {
            m.label = l >= 2 ? "低落" : "有点闷"
            m.valence = max(0.1, 0.5 - Double(l) * 0.15)
            m.energy = 0.35
            m.note = "对话里负面词偏多"
        } else if h > l {
            m.label = "开心"
            m.valence = min(0.95, 0.6 + Double(h) * 0.1)
            m.energy = 0.65
            m.note = "对话里正面词偏多"
        } else {
            m.label = "平静"
            m.valence = 0.6
            m.energy = 0.5
        }
        m.updatedAt = Date()
        return m
    }
}

// MARK: - 详情页
struct MoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MoodStore.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Text(store.current.emoji).font(.system(size: 44))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.current.label).font(.headline)
                            Text("愉快 \(Int(store.current.valence * 100))% · 精力 \(Int(store.current.energy * 100))%")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !store.current.note.isEmpty {
                        Text(store.current.note).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("现在的状态")
                } footer: {
                    Text("每轮对话后由模型自动判断，随对话变化。你也可以手动调。")
                }

                Section("手动调整") {
                    HStack {
                        Text("愉快度")
                        Slider(value: Binding(
                            get: { store.current.valence },
                            set: { store.adjust(valence: $0) }
                        ), in: 0...1)
                    }
                    HStack {
                        Text("精力")
                        Slider(value: Binding(
                            get: { store.current.energy },
                            set: { store.adjust(energy: $0) }
                        ), in: 0...1)
                    }
                    Picker("心情", selection: Binding(
                        get: { store.current.label },
                        set: { store.adjust(label: $0) }
                    )) {
                        ForEach(["平静", "开心", "低落", "疲惫", "兴奋", "黏人", "有点闷"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                }
            }
            .themedScroll(.settings)
            .navigationTitle("情绪")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
