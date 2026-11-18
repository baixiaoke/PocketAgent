import Foundation
import SwiftUI

struct KBChunk: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var path: String
    var text: String
}

/// 本地知识库：把授权文件夹里的文本切块索引，用关键词检索。
/// 不上传、不调模型，纯本地。
final class KnowledgeBase: ObservableObject {
    static let shared = KnowledgeBase()

    @Published private(set) var chunks: [KBChunk] = []
    @Published private(set) var indexedFiles = 0
    @Published private(set) var lastIndexed: Date?
    @Published private(set) var indexing = false

    private let url: URL
    private let maxChunks = 4000
    private let chunkSize = 700
    private let overlap = 80

    private static let textExts: Set<String> = [
        "txt", "md", "markdown", "json", "csv", "swift", "py", "js", "ts",
        "html", "htm", "xml", "yml", "yaml", "log", "sh", "sql", "rtf"
    ]

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = docs.appendingPathComponent("kb.json")
        if let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([KBChunk].self, from: data) {
            chunks = list
            lastIndexed = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(chunks) else { return }
        try? data.write(to: url, options: .atomic)
        lastIndexed = Date()
    }

    /// 扫描文件夹重建索引
    func index(folder: URL, progress: ((Int) -> Void)? = nil) {
        indexing = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            var built: [KBChunk] = []
            var files = 0

            let fm = FileManager.default
            let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
            guard let walker = fm.enumerator(at: folder, includingPropertiesForKeys: keys) else {
                DispatchQueue.main.async { self.indexing = false }
                return
            }

            for case let file as URL in walker {
                if built.count >= self.maxChunks { break }
                let ext = file.pathExtension.lowercased()
                guard Self.textExts.contains(ext) else { continue }
                guard let vals = try? file.resourceValues(forKeys: Set(keys)),
                      vals.isRegularFile == true,
                      (vals.fileSize ?? 0) < 2_000_000 else { continue }

                guard let raw = try? String(contentsOf: file, encoding: .utf8) else { continue }
                files += 1
                let relative = file.path.replacingOccurrences(of: folder.path, with: "")
                for piece in Self.split(raw) {
                    built.append(KBChunk(path: relative, text: piece))
                    if built.count >= self.maxChunks { break }
                }
                if files % 20 == 0 {
                    DispatchQueue.main.async { progress?(built.count) }
                }
            }

            DispatchQueue.main.async {
                self.chunks = built
                self.indexedFiles = files
                self.indexing = false
                self.save()
                progress?(built.count)
            }
        }
    }

    private static func split(_ text: String) -> [String] {
        let clean = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard clean.count > 80 else { return clean.count > 20 ? [clean] : [] }
        var out: [String] = []
        var start = clean.startIndex
        while start < clean.endIndex {
            let end = clean.index(start, offsetBy: 700, limitedBy: clean.endIndex) ?? clean.endIndex
            let piece = String(clean[start..<end])
            if piece.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 {
                out.append(piece)
            }
            if end == clean.endIndex { break }
            start = clean.index(end, offsetBy: -80, limitedBy: clean.startIndex) ?? end
        }
        return out
    }

    /// 关键词打分检索
    func search(_ query: String, limit: Int = 6) -> [KBChunk] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !chunks.isEmpty else { return [] }

        // 拆词：中文按 2 字滑窗，英文按空白
        var terms: [String] = []
        let latin = q.split(whereSeparator: { $0 == " " || $0 == "，" || $0 == "," })
        for w in latin where w.count >= 2 {
            terms.append(String(w).lowercased())
        }
        let chars = Array(q)
        if chars.count >= 4 {
            for i in 0..<(chars.count - 1) {
                terms.append(String(chars[i...i + 1]))
            }
        }

        var scored: [(KBChunk, Int)] = []
        for c in chunks {
            let lower = c.text.lowercased()
            var score = 0
            for t in terms where lower.contains(t) { score += t.count >= 3 ? 3 : 1 }
            if score > 0 { scored.append((c, score)) }
        }
        scored.sort { $0.1 > $1.1 }
        return scored.prefix(limit).map { $0.0 }
    }

    func clear() {
        chunks = []
        indexedFiles = 0
        lastIndexed = nil
        save()
    }
}
