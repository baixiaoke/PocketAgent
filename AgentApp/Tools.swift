import Foundation
import UIKit
import EventKit
import UserNotifications

/// agent 的「手」：全部是 iOS 原生能力，没有一个子进程。
/// 每个工具都限制在 App 自己的沙盒里，出不了 Documents 目录。
final class ToolRegistry {

    private let docs: URL
    private let decoder = JSONDecoder()

    init(documents: URL) {
        self.docs = documents.standardizedFileURL
    }

    // MARK: - 给模型的工具清单
    var specs: [ToolSpec] {
        [
            ToolSpec(name: "now",
                     description: "获取设备当前时间（含时区）。任何涉及“今天/明天/几点了”的问题都先调它。",
                     parameters: obj([:], required: [])),

            ToolSpec(name: "list_files",
                     description: "列出沙盒 Documents 目录下的文件。path 传空或 \".\" 表示根目录。",
                     parameters: obj(["path": str("相对路径，可为空")], required: [])),

            ToolSpec(name: "read_file",
                     description: "读取沙盒内一个文本文件的内容（最多 20000 字符）。",
                     parameters: obj(["path": str("相对 Documents 的路径")], required: ["path"])),

            ToolSpec(name: "write_file",
                     description: "把文本写入沙盒内文件，自动创建父目录，覆盖同名文件。用来保存笔记、清单、代码。",
                     parameters: obj(["path": str("相对 Documents 的路径"),
                                      "content": str("要写入的完整文本")],
                                     required: ["path", "content"])),

            ToolSpec(name: "http_get",
                     description: "GET 一个 http(s) 地址并返回响应正文（最多 20000 字符）。查资料、调公开 API 用它。",
                     parameters: obj(["url": str("完整 URL"),
                                      "max_chars": num("返回上限，默认 20000")],
                                     required: ["url"])),

            ToolSpec(name: "clipboard_get",
                     description: "读取系统剪贴板文本。",
                     parameters: obj([:], required: [])),

            ToolSpec(name: "clipboard_set",
                     description: "把文本写进系统剪贴板，用户可直接粘贴到别处。",
                     parameters: obj(["text": str("要复制的内容")], required: ["text"])),

            ToolSpec(name: "open_url",
                     description: "用系统浏览器/对应 App 打开一个 URL（http、https 或 App 的 URL scheme）。",
                     parameters: obj(["url": str("完整 URL")], required: ["url"])),

            ToolSpec(name: "notify",
                     description: "发一条本地通知到通知中心。适合提醒用户长任务已完成。",
                     parameters: obj(["title": str("标题"), "body": str("正文")],
                                     required: ["title", "body"])),

            ToolSpec(name: "add_reminder",
                     description: "在系统「提醒事项」里新建一条待办。",
                     parameters: obj(["title": str("待办标题"),
                                      "notes": str("备注，可为空")],
                                     required: ["title"])),

            ToolSpec(name: "folder_list",
                     description: "列出用户已授权的外部文件夹里的内容（iCloud Drive、下载目录等）。用户没授权就返回提示。",
                     parameters: obj(["path": str("相对该文件夹的路径，可为空")], required: [])),

            ToolSpec(name: "folder_read",
                     description: "读取用户已授权的外部文件夹里的文本文件（最多 20000 字符）。",
                     parameters: obj(["path": str("相对该文件夹的文件路径")], required: ["path"])),

            ToolSpec(name: "remember",
                     description: "把一条关于用户的长期事实写进记忆（住哪、做什么、在意什么、讨厌什么、约定）。下一轮对话会自动带上。",
                     parameters: obj(["fact": str("一句话事实，例如「他在杭州，养了一只橘猫」"),
                                      "importance": num("1 普通 / 2 重要 / 3 别忘，默认 1")],
                                     required: ["fact"])),

            ToolSpec(name: "recall",
                     description: "在长期记忆里检索。用户问「你还记得…」时先调它。",
                     parameters: obj(["query": str("关键词，可为空表示看全部")], required: [])),

            ToolSpec(name: "web_read",
                     description: "抓网页并只留正文（去掉导航、广告、脚本），比 http_get 干净。读文章用它。",
                     parameters: obj(["url": str("完整 URL")], required: ["url"])),

            ToolSpec(name: "weather",
                     description: "查当前位置或指定城市的天气。不传城市就用设备定位。",
                     parameters: obj(["city": str("城市名，可为空")], required: [])),

            ToolSpec(name: "where_am_i",
                     description: "获取设备当前所在城市（需定位权限）。",
                     parameters: obj([:], required: [])),

            ToolSpec(name: "kb_index",
                     description: "把用户授权的外部文件夹重建索引，供 kb_search 检索。文件夹没授权就提示用户去连接。",
                     parameters: obj([:], required: [])),

            ToolSpec(name: "kb_search",
                     description: "在本地知识库里检索用户文档的片段。问「我那份文件里怎么写的」时用它。",
                     parameters: obj(["query": str("要查的内容"), "limit": num("返回几条，默认 5")],
                                     required: ["query"])),
        ]
    }

    // MARK: - 执行
    func run(name: String, argumentsJSON: String) async -> (content: String, isError: Bool) {
        let args = (try? JSONSerialization.jsonObject(
            with: Data((argumentsJSON.isEmpty ? "{}" : argumentsJSON).utf8)
        ) as? [String: Any]) ?? [:]

        do {
            switch name {
            case "now":
                let f = DateFormatter()
                f.locale = Locale(identifier: "zh_CN")
                f.dateFormat = "yyyy年M月d日 EEEE HH:mm:ss"
                let tz = TimeZone.current.identifier
                return ("当前时间：\(f.string(from: Date()))（\(tz)）", false)

            case "list_files":
                let dir = resolve(args["path"] as? String ?? "") ?? docs
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) else {
                    return ("路径不存在：\(dir.lastPathComponent)", true)
                }
                let items = (try? FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey])) ?? []
                if items.isEmpty { return ("（空目录：\(rel(dir))）", false) }
                let lines = items.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { u -> String in
                    let vals = try? u.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                    if vals?.isDirectory == true { return "\(u.lastPathComponent)/" }
                    return "\(u.lastPathComponent)  \(vals?.fileSize ?? 0) bytes"
                }
                return ("目录 \(rel(dir))：\n" + lines.joined(separator: "\n"), false)

            case "read_file":
                guard let url = resolve(args["path"] as? String ?? "") else {
                    return ("路径越界（只能读写 App 沙盒内文件）", true)
                }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                    return ("读不到：\(rel(url))", true)
                }
                return (String(text.prefix(20_000)), false)

            case "write_file":
                guard let url = resolve(args["path"] as? String ?? "") else {
                    return ("路径越界（只能读写 App 沙盒内文件）", true)
                }
                let content = args["content"] as? String ?? ""
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: url, atomically: true, encoding: .utf8)
                return ("已写入 \(rel(url))（\(content.utf8.count) 字节）", false)

            case "http_get":
                guard let raw = args["url"] as? String, let url = URL(string: raw) else {
                    return ("URL 不合法", true)
                }
                var req = URLRequest(url: url)
                req.timeoutInterval = 30
                req.setValue("PocketAgent/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
                let (data, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                let limit = (args["max_chars"] as? Int) ?? 20_000
                let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? "<二进制 \(data.count) 字节>"
                return ("HTTP \(code)\n" + String(text.prefix(limit)), false)

            case "clipboard_get":
                let text = await MainActor.run { UIPasteboard.general.string ?? "" }
                return (text.isEmpty ? "（剪贴板为空）" : text, false)

            case "clipboard_set":
                let text = args["text"] as? String ?? ""
                await MainActor.run { UIPasteboard.general.string = text }
                return ("已复制 \(text.count) 个字符到剪贴板", false)

            case "open_url":
                guard let raw = args["url"] as? String, let url = URL(string: raw) else {
                    return ("URL 不合法", true)
                }
                let ok = await MainActor.run { UIApplication.shared.canOpenURL(url) }
                guard ok else { return ("系统拒绝打开：\(raw)", true) }
                await MainActor.run { UIApplication.shared.open(url) }
                return ("已交给系统打开：\(raw)", false)

            case "notify":
                let title = args["title"] as? String ?? "PocketAgent"
                let body = args["body"] as? String ?? ""
                try await NotificationCenterBox.post(title: title, body: body)
                return ("通知已发出", false)

            case "add_reminder":
                let title = args["title"] as? String ?? ""
                guard !title.isEmpty else { return ("标题不能为空", true) }
                let notes = args["notes"] as? String ?? ""
                return try await RemindersBox.add(title: title, notes: notes)

            case "folder_list":
                guard let root = ExternalFolder.shared.root else {
                    return ("用户还没授权任何外部文件夹。请让他在 App 右上角 ⋯ → 连接文件夹 里选一个。", true)
                }
                guard let dir = ExternalFolder.shared.resolve(args["path"] as? String ?? "") else {
                    return ("路径越界（只能访问已授权文件夹内部）", true)
                }
                let items = (try? FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey])) ?? []
                if items.isEmpty {
                    return ("（空目录：\(ExternalFolder.shared.relativePath(dir))）", false)
                }
                let lines = items.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { u -> String in
                    let v = try? u.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                    if v?.isDirectory == true { return "\(u.lastPathComponent)/" }
                    return "\(u.lastPathComponent)  \(v?.fileSize ?? 0) bytes"
                }
                return ("外部文件夹「\(root.lastPathComponent)」/ \(ExternalFolder.shared.relativePath(dir))：\n"
                        + lines.joined(separator: "\n"), false)

            case "folder_read":
                guard ExternalFolder.shared.root != nil else {
                    return ("用户还没授权任何外部文件夹。请让他在 App 右上角 ⋯ → 连接文件夹 里选一个。", true)
                }
                guard let url = ExternalFolder.shared.resolve(args["path"] as? String ?? "") else {
                    return ("路径越界（只能访问已授权文件夹内部）", true)
                }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                    return ("读不到：\(url.lastPathComponent)", true)
                }
                return (String(text.prefix(20_000)), false)

            case "remember":
                let fact = args["fact"] as? String ?? ""
                let imp = (args["importance"] as? Int) ?? 1
                guard !fact.trimmingCharacters(in: .whitespaces).isEmpty else {
                    return ("事实不能为空", true)
                }
                let added = LongTermMemory.shared.add(fact, importance: imp)
                return (added ? "记住了：\(fact)" : "这条已经记过了", false)

            case "recall":
                let q = args["query"] as? String ?? ""
                let hits = LongTermMemory.shared.search(q)
                if hits.isEmpty { return ("没有相关记忆。", false) }
                let lines = hits.map { "- \($0.text)（\($0.when)）" }
                return ("记得这些：\n" + lines.joined(separator: "\n"), false)

            case "web_read":
                guard let raw = args["url"] as? String, let url = URL(string: raw) else {
                    return ("URL 不合法", true)
                }
                var req = URLRequest(url: url)
                req.timeoutInterval = 25
                req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
                do {
                    let (data, resp) = try await URLSession.shared.data(for: req)
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                    let html = String(data: data, encoding: .utf8) ?? ""
                    let body = WebText.extract(html)
                    return ("HTTP \(code) · 正文 \(body.count) 字\n\n" + String(body.prefix(12_000)), false)
                } catch {
                    return ("抓取失败：\(error.localizedDescription)", true)
                }

            case "weather":
                if let city = args["city"] as? String, !city.isEmpty {
                    let url = "https://wttr.in/\(city.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? city)?format=%25l:+%25c+%25t+(%25f)+%25w+%25h&lang=zh"
                    if let u = URL(string: url) {
                        var req = URLRequest(url: u); req.timeoutInterval = 15
                        req.setValue("curl/8", forHTTPHeaderField: "User-Agent")
                        if let (d, _) = try? await URLSession.shared.data(for: req),
                           let t = String(data: d, encoding: .utf8), !t.isEmpty {
                            return (t.trimmingCharacters(in: .whitespacesAndNewlines), false)
                        }
                    }
                    return ("天气服务暂时不可用", true)
                }
                guard let loc = await LocationBox.shared.current() else {
                    return ("拿不到定位。可以在设置里允许定位，或者直接告诉我城市名。", true)
                }
                let text = await WeatherBox.fetch(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
                return (text, false)

            case "where_am_i":
                guard let loc = await LocationBox.shared.current() else {
                    return ("拿不到定位（可能没给权限）", true)
                }
                let name = await LocationBox.shared.placeName(loc) ?? "未知"
                return ("当前位置：\(name)（\(String(format: "%.3f", loc.coordinate.latitude)), \(String(format: "%.3f", loc.coordinate.longitude))）", false)

            case "kb_index":
                guard let root = ExternalFolder.shared.root else {
                    return ("用户还没授权文件夹。让他去右上角 ⋯ → 连接文件夹。", true)
                }
                KnowledgeBase.shared.index(folder: root)
                return ("开始重建索引，稍后用 kb_search 查。", false)

            case "kb_search":
                let q = args["query"] as? String ?? ""
                let limit = (args["limit"] as? Int) ?? 5
                let hits = KnowledgeBase.shared.search(q, limit: limit)
                if hits.isEmpty {
                    if KnowledgeBase.shared.chunks.isEmpty {
                        return ("知识库是空的。先让用户授权文件夹，再调 kb_index。", true)
                    }
                    return ("没检索到相关内容。", false)
                }
                var out = ""
                for (i, h) in hits.enumerated() {
                    out += "[\(i + 1)] \(h.path)\n\(h.text.prefix(600))\n\n"
                }
                return (out, false)

            default:
                return ("没有这个工具：\(name)", true)
            }
        } catch {
            return ("工具执行失败：\(error.localizedDescription)", true)
        }
    }

    // MARK: - 路径
    private func resolve(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: URL
        if trimmed.isEmpty || trimmed == "." || trimmed == "/" {
            candidate = docs
        } else if trimmed.hasPrefix("file://"), let u = URL(string: trimmed) {
            candidate = u
        } else if trimmed.hasPrefix("/") {
            candidate = URL(fileURLWithPath: trimmed)
        } else {
            candidate = docs.appendingPathComponent(trimmed)
        }
        let std = candidate.standardizedFileURL
        guard std.path == docs.path || std.path.hasPrefix(docs.path + "/") else { return nil }
        return std
    }

    private func rel(_ url: URL) -> String {
        let p = url.standardizedFileURL.path
        if p == docs.path { return "." }
        return String(p.dropFirst(docs.path.count + 1))
    }

    // MARK: - JSON Schema 小工具
    private func obj(_ props: [String: Any], required: [String]) -> [String: Any] {
        ["type": "object", "properties": props, "required": required]
    }
    private func str(_ desc: String) -> [String: Any] { ["type": "string", "description": desc] }
    private func num(_ desc: String) -> [String: Any] { ["type": "integer", "description": desc] }
}

// MARK: - 通知
enum NotificationCenterBox {
    static func post(title: String, body: String) async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        guard granted else { throw NSError(domain: "notify", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "用户没给通知权限"]) }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try await center.add(req)
    }
}

// MARK: - 提醒事项
enum RemindersBox {
    static func add(title: String, notes: String) async throws -> (String, Bool) {
        let store = EKEventStore()
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = (try? await store.requestFullAccessToReminders()) ?? false
        } else {
            granted = await withCheckedContinuation { cont in
                store.requestAccess(to: .reminder) { ok, _ in cont.resume(returning: ok) }
            }
        }
        guard granted else { return ("用户没给提醒事项权限", true) }

        guard let calendar = store.defaultCalendarForNewReminders() else {
            return ("这台设备上没有默认提醒列表", true)
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = calendar
        try store.save(reminder, commit: true)
        return ("已加入提醒事项：\(title)", false)
    }
}
