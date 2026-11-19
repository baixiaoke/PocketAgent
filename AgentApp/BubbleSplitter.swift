import Foundation

/// 把一条回复拆成「像人连发」的几条
enum BubbleSplitter {

    /// 优先按 ||| 拆；模型没写就按句末标点自动拆（长文、代码、列表不拆）
    static func split(_ text: String) -> [String] {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }

        if raw.contains("|||") {
            return raw.components(separatedBy: "|||")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        // 长文/代码/多行不拆，避免把正经内容打散
        let looksLong = raw.count > 160
        let looksCode = raw.contains("```") || raw.contains("\n- ") || raw.contains("\n1.")
        let multiLine = raw.filter { $0 == "\n" }.count >= 2
        if looksLong || looksCode || multiLine { return [raw] }

        var parts: [String] = []
        var current = ""
        let enders: Set<Character> = ["。", "！", "？", "…", "!", "?"]
        for ch in raw {
            current.append(ch)
            if enders.contains(ch) {
                let t = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { parts.append(t) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { parts.append(tail) }

        if parts.count < 2 { return [raw] }
        if parts.count > 5 {
            let head = Array(parts.prefix(4))
            let rest = parts.dropFirst(4).joined()
            return head + [rest]
        }
        return parts
    }

    /// 假装在打字：按字数估一个延迟（0.5–2.4 秒）
    static func typingDelay(for text: String) -> Double {
        let perChar = 0.045
        let base = 0.45
        let d = base + Double(text.count) * perChar
        return min(2.4, max(0.5, d))
    }
}
