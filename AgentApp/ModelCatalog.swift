import Foundation

/// 模型 / 音色探测：尽量兼容各家 OpenAI 风格与常见变体
enum ModelCatalog {

    struct ModelResult {
        var models: [String] = []
        var error: String?
    }

    // MARK: - 根地址归一
    /// 把各种尾巴（/chat/completions、/images/generations…）削成根
    static func root(of base: String) -> String {
        var s = base.trimmingCharacters(in: .whitespaces)
        while s.hasSuffix("/") { s.removeLast() }
        let tails = ["/chat/completions", "/images/generations", "/audio/speech",
                     "/models", "/images", "/audio"]
        for t in tails where s.hasSuffix(t) {
            s = String(s.dropLast(t.count))
        }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private static func candidates(_ base: String, _ path: String) -> [URL] {
        let r = root(of: base)
        let list = ["\(r)\(path)", "\(r)/v1\(path)"]
        return list.compactMap { URL(string: $0) }
    }

    // MARK: - 列模型
    static func listModels(base: String, apiKey: String) async -> ModelResult {
        guard !base.trimmingCharacters(in: .whitespaces).isEmpty else {
            return ModelResult(models: [], error: "先填接口地址")
        }
        guard !apiKey.isEmpty else {
            return ModelResult(models: [], error: "先填 API Key")
        }

        var lastError = ""
        for url in candidates(base, "/models") {
            var req = URLRequest(url: url)
            req.timeoutInterval = 25
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                guard (200..<300).contains(code) else {
                    lastError = "HTTP \(code)"
                    continue
                }
                if let ids = parseModelIDs(data), !ids.isEmpty {
                    return ModelResult(models: ids, error: nil)
                }
                lastError = "返回里没找到模型列表"
            } catch {
                lastError = error.localizedDescription
            }
        }
        return ModelResult(models: [], error: lastError.isEmpty ? "探测失败" : lastError)
    }

    private static func parseModelIDs(_ data: Data) -> [String]? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let arr = obj["data"] as? [[String: Any]] {
                return arr.compactMap { $0["id"] as? String }
            }
            if let arr = obj["models"] as? [[String: Any]] {
                return arr.compactMap { ($0["id"] as? String) ?? ($0["name"] as? String) }
            }
            if let arr = obj["data"] as? [String] {
                return arr
            }
        }
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return arr
        }
        return nil
    }

    // MARK: - 列音色
    static let builtinVoices = [
        "alloy", "echo", "fable", "onyx", "nova", "shimmer",
        "longxiaochun", "longyuanxiang", "zhiyan", "zhimi"
    ]

    static func listVoices(base: String, apiKey: String) async -> ([String], String?) {
        guard !base.isEmpty, !apiKey.isEmpty else { return (builtinVoices, "用内置音色列表") }

        for path in ["/voices", "/audio/voices", "/voice/list"] {
            for url in candidates(base, path) {
                var req = URLRequest(url: url)
                req.timeoutInterval = 20
                req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                guard let (data, resp) = try? await URLSession.shared.data(for: req),
                      let http = resp as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else { continue }

                if let names = parseVoiceNames(data), !names.isEmpty {
                    return (names, nil)
                }
            }
        }
        return (builtinVoices, "该服务没提供音色列表接口，已列内置常用音色")
    }

    private static func parseVoiceNames(_ data: Data) -> [String]? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let arr = obj["data"] as? [[String: Any]] {
            let names = arr.compactMap { ($0["voice_id"] as? String) ?? ($0["id"] as? String) ?? ($0["name"] as? String) }
            if !names.isEmpty { return names }
        }
        if let arr = obj["voices"] as? [[String: Any]] {
            let names = arr.compactMap { ($0["voice_id"] as? String) ?? ($0["id"] as? String) ?? ($0["name"] as? String) }
            if !names.isEmpty { return names }
        }
        return nil
    }

    // MARK: - 克隆声音
    /// ElevenLabs 风格：POST /voices/add（multipart: name + files[]）
    /// 不同厂商字段不同，这里按最常见格式提交，成功后返回服务端给的 voice_id
    static func cloneVoice(base: String,
                           apiKey: String,
                           name: String,
                           audio: Data,
                           filename: String) async -> (String?, String?) {
        guard !base.isEmpty, !apiKey.isEmpty else { return (nil, "先填接口地址和 Key") }

        let boundary = "----PocketAgent\(Int(Date().timeIntervalSince1970))"
        var body = Data()

        func field(_ k: String, _ v: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(k)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(v)\r\n".data(using: .utf8)!)
        }

        field("name", name)
        field("description", "PocketAgent 克隆音色")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mpeg\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var lastError = ""
        for path in ["/voices/add", "/voice/clone", "/audio/voices"] {
            for url in candidates(base, path) {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.timeoutInterval = 120
                req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                req.httpBody = body
                do {
                    let (data, resp) = try await URLSession.shared.data(for: req)
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                    if (200..<300).contains(code) {
                        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            let id = (obj["voice_id"] as? String) ?? (obj["id"] as? String) ?? (obj["data"] as? [String: Any])?["voice_id"] as? String
                            return (id ?? "已提交", nil)
                        }
                        return ("已提交", nil)
                    }
                    let msg = String(data: data, encoding: .utf8) ?? ""
                    lastError = "HTTP \(code) \(msg.prefix(120))"
                } catch {
                    lastError = error.localizedDescription
                }
            }
        }
        return (nil, lastError.isEmpty ? "该服务不支持克隆，或接口路径不同" : lastError)
    }
}
