import Foundation
import SwiftUI

/// 整包备份 / 恢复：会话、记忆、人格、知识库索引一次打包
enum Backup {

    static let keys = ["sessions.json", "memory.json", "persona.json", "kb.json"]

    struct Bundle: Codable {
        var version: Int = 1
        var exportedAt: Date = Date()
        var files: [String: String] = [:]     // 文件名 → 原始 JSON 文本
    }

    static func documentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// 打包成单个文件，返回临时文件 URL
    static func export() -> URL? {
        let docs = documentsURL()
        var b = Bundle()
        for name in keys {
            let f = docs.appendingPathComponent(name)
            if let text = try? String(contentsOf: f, encoding: .utf8) {
                b.files[name] = text
            }
        }
        guard !b.files.isEmpty else { return nil }

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(b) else { return nil }

        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PocketAgent-备份-\(f.string(from: Date())).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch { return nil }
    }

    /// 从备份文件恢复，返回写入了几个文件
    static func restore(from url: URL) -> Int {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { return 0 }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let b = try? dec.decode(Bundle.self, from: data) else { return 0 }

        let docs = documentsURL()
        var written = 0
        for (name, text) in b.files where keys.contains(name) {
            let f = docs.appendingPathComponent(name)
            do {
                try text.write(to: f, atomically: true, encoding: .utf8)
                written += 1
            } catch { }
        }

        // 重新载入各单例
        if written > 0 {
            LongTermMemory.shared.load()
            PersonaStore.shared.load()
            KnowledgeBase.shared.clear()
        }
        return written
    }

    static func sizeText() -> String {
        let docs = documentsURL()
        var total = 0
        for name in keys {
            let f = docs.appendingPathComponent(name)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: f.path),
               let size = attrs[.size] as? Int {
                total += size
            }
        }
        if total < 1024 { return "\(total) B" }
        if total < 1024 * 1024 { return String(format: "%.1f KB", Double(total) / 1024) }
        return String(format: "%.1f MB", Double(total) / 1024 / 1024)
    }
}

/// 字号档位
enum FontScale: String, CaseIterable, Identifiable {
    case small = "小"
    case normal = "标准"
    case large = "大"
    case xlarge = "特大"

    var id: String { rawValue }

    var dynamicType: DynamicTypeSize {
        switch self {
        case .small:  return .small
        case .normal: return .large      // 系统默认偏大，这里对齐「标准」
        case .large:  return .xLarge
        case .xlarge: return .xxxLarge
        }
    }
}
