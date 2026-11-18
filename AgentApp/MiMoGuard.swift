import Foundation

/// 给小米 TTS 加的四层防护：本地限速、磁盘缓存、429 退避、分段合并
enum MiMoGuard {

    // MARK: 本地限速（令牌桶的简化版：两次请求至少间隔 N 秒）
    /// 最小请求间隔，避免瞬时并发
    static var minInterval: TimeInterval = 1.0
    private static var lastAt = Date.distantPast
    private static let lock = NSLock()

    static func waitTurn() async {
        lock.lock()
        let now = Date()
        let elapsed = now.timeIntervalSince(lastAt)
        let need = max(0, minInterval - elapsed)
        lastAt = now.addingTimeInterval(need)
        lock.unlock()
        if need > 0 {
            try? await Task.sleep(nanoseconds: UInt64(need * 1_000_000_000))
        }
    }

    // MARK: 磁盘缓存
    private static func cacheDir() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("voice/cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func key(_ text: String, voice: String, style: String, model: String) -> String {
        let raw = model + "|" + voice + "|" + style + "|" + text
        var hash: UInt64 = 1469598103934665603
        for b in raw.utf8 {
            hash = (hash ^ UInt64(b)) &* 1099511628211
        }
        return String(hash, radix: 16)
    }

    static func cached(_ text: String, voice: String, style: String, model: String) -> Data? {
        let f = cacheDir().appendingPathComponent(key(text, voice: voice, style: style, model: model) + ".wav")
        guard let d = try? Data(contentsOf: f), !d.isEmpty else { return nil }
        return d
    }

    static func store(_ data: Data, text: String, voice: String, style: String, model: String) {
        let f = cacheDir().appendingPathComponent(key(text, voice: voice, style: style, model: model) + ".wav")
        try? data.write(to: f, options: .atomic)
        trimCache()
    }

    /// 缓存上限 60MB，超了按时间删旧的
    private static func trimCache() {
        let dir = cacheDir()
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir,
                                                                     includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return }
        var total = 0
        var infos: [(URL, Date, Int)] = []
        for f in files {
            let v = try? f.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let size = v?.fileSize ?? 0
            let date = v?.contentModificationDate ?? Date.distantPast
            total += size
            infos.append((f, date, size))
        }
        guard total > 60_000_000 else { return }
        for (url, _, size) in infos.sorted(by: { $0.1 < $1.1 }) {
            try? FileManager.default.removeItem(at: url)
            total -= size
            if total <= 40_000_000 { break }
        }
    }

    static func cacheSize() -> Int {
        let dir = cacheDir()
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir,
                                                                     includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { sum, f in
            sum + ((try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }

    static func clearCache() {
        let dir = cacheDir()
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: 429 处理
    /// 从响应头里读 Retry-After
    static func retryAfter(_ resp: HTTPURLResponse?) -> TimeInterval? {
        guard let raw = resp?.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let secs = Double(raw) { return secs }
        return nil
    }
}
