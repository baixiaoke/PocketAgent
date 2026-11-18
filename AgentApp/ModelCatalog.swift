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
    /// 各家字段不一样，这里按三种最常见格式轮着试，并记录每一步服务端原话
    enum CloneFormat: String, CaseIterable, Identifiable {
        case generic = "通用 multipart"
        case eleven  = "ElevenLabs 风格"
        case miniMax = "MiniMax 风格"
        var id: String { rawValue }
    }

    struct CloneResult {
        var voiceID: String?
        var log: String = ""
        var verified: Bool = false
    }

    static func cloneVoice(base: String,
                           apiKey: String,
                           name: String,
                           audio: Data,
                           filename: String,
                           format: CloneFormat,
                           settingsForVerify: AgentSettings? = nil,
                           fallbackKey: String = "") async -> CloneResult {
        var result = CloneResult()
        guard !base.isEmpty, !apiKey.isEmpty else {
            result.log = "先填接口地址和 Key"
            return result
        }

        let boundary = "----PocketAgent\(Int(Date().timeIntervalSince1970))"

        func build(fields: [(String, String)], fileField: String) -> Data {
            var body = Data()
            for (k, v) in fields {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(k)\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(v)\r\n".data(using: .utf8)!)
            }
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/mpeg\r\n\r\n".data(using: .utf8)!)
            body.append(audio)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            return body
        }

        // 每家：路径 + 字段
        var plans: [(path: String, body: Data)] = []
        switch format {
        case .generic:
            plans = [
                ("/voices/add", build(fields: [("name", name), ("description", "PocketAgent 克隆音色")], fileField: "files")),
                ("/voice/clone", build(fields: [("name", name), ("voice_name", name)], fileField: "file"))
            ]
        case .eleven:
            plans = [
                ("/v1/voices/add", build(fields: [("name", name), ("description", "PocketAgent")], fileField: "files"))
            ]
        case .miniMax:
            plans = [
                ("/v1/voice/clone", build(fields: [("voice_id", name), ("name", name)], fileField: "file")),
                ("/v1/voice/upload", build(fields: [("voice_id", name)], fileField: "file"))
            ]
        }

        for plan in plans {
            for url in candidates(base, plan.path) {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.timeoutInterval = 150
                req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                req.httpBody = plan.body

                do {
                    let (data, resp) = try await URLSession.shared.data(for: req)
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                    let text = String(data: data, encoding: .utf8) ?? ""
                    result.log += "[\(plan.path)] HTTP \(code)：\(text.prefix(180))\n"

                    guard (200..<300).contains(code) else { continue }

                    // 取 voice id
                    var vid: String?
                    if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        vid = (obj["voice_id"] as? String)
                            ?? (obj["id"] as? String)
                            ?? ((obj["data"] as? [String: Any])?["voice_id"] as? String)
                    }
                    result.voiceID = vid ?? name

                    // 立刻验证：拿这个音色合成一句，能出声才算成功
                    if let s = settingsForVerify, let v = result.voiceID {
                        var test = s
                        test.ttsVoice = v
                        if let audio = await VoiceOut.fetchSpeech("测试", settings: test, fallbackKey: fallbackKey),
                           !audio.isEmpty {
                            result.verified = true
                            result.log += "验证通过：用「\(v)」合成成功（\(audio.count) 字节）\n"
                        } else {
                            result.log += "验证失败：拿「\(v)」合成不出音频（可能是 id 不对，或该服务不支持这个音色）\n"
                        }
                    }
                    return result
                } catch {
                    result.log += "[\(plan.path)] 请求异常：\(error.localizedDescription)\n"
                }
            }
        }
        return result
    }
}
