import Foundation

/// 小米 MiMo 语音：按 aurabot 的稳定做法实现
/// 要点：整段一次合成、不分段、不重试、audio 只带必要字段
enum MiMoVoice {

    /// 最近一次失败原因（给界面显示）
    static var lastError: String = ""

    /// 官方内置音色（仅 mimo-v2.5-tts 模型支持）
    static let builtinVoiceIDs = [
        "mimo_default", "冰糖", "茉莉", "苏打", "白桦",
        "Mia", "Chloe", "Milo", "Dean"
    ]

    // MARK: - 音色描述（voicedesign）
    static let defaultDescNormal = "二十岁左右的女生，女声，音色软一点，带气声，说话随意，句子中间会换气，不播音不念稿"

    static let defaultDescHot = "二十岁左右的女生，女声，贴着耳朵的气声，喘息很重，句子断断续续，说半句就软下去，尾音发抖，像被弄得说不出话，偶尔漏出一点鼻音"

    /// 命中这些词就切成人音色（纯拟声词会被判高风险，必须带实词）
    static let hotWords = [
        "轻一点", "受不了", "别停", "好深", "要坏", "顶到", "湿了",
        "呻吟", "喘", "抱我", "进来", "啊…", "嗯…", "哼…",
        "不要了", "好舒服"
    ]

    static func isHot(_ text: String) -> Bool {
        hotWords.contains { text.contains($0) }
    }

    /// 判断是不是该走 MiMo 协议
    static func looksLikeMiMo(model: String, base: String) -> Bool {
        let m = model.lowercased()
        let b = base.lowercased()
        return m.hasPrefix("mimo-") || m.contains("mimo-v") || b.contains("xiaomimimo")
    }

    // MARK: - 参考音频（克隆用）
    private static func voiceDir() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("voice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var referenceURL: URL { voiceDir().appendingPathComponent("reference.wav") }
    static var referenceURLMP3: URL { voiceDir().appendingPathComponent("reference.mp3") }

    static func currentReferenceFile() -> URL? {
        if FileManager.default.fileExists(atPath: referenceURL.path) { return referenceURL }
        if FileManager.default.fileExists(atPath: referenceURLMP3.path) { return referenceURLMP3 }
        return nil
    }

    static func referenceMIME() -> String {
        guard let f = currentReferenceFile() else { return "audio/wav" }
        return f.pathExtension.lowercased() == "mp3" ? "audio/mpeg" : "audio/wav"
    }

    static func hasReference() -> Bool { currentReferenceFile() != nil }

    static func referenceSize() -> Int {
        guard let f = currentReferenceFile() else { return 0 }
        return (try? Data(contentsOf: f).count) ?? 0
    }

    /// 保存参考音频：wav 存 .wav，其它存 .mp3
    static func saveReference(_ data: Data) throws {
        let isWav = data.count > 4 && String(data: data.prefix(4), encoding: .ascii) == "RIFF"
        try? FileManager.default.removeItem(at: isWav ? referenceURLMP3 : referenceURL)
        try data.write(to: isWav ? referenceURL : referenceURLMP3, options: .atomic)
    }

    static func clearReference() {
        try? FileManager.default.removeItem(at: referenceURL)
        try? FileManager.default.removeItem(at: referenceURLMP3)
    }

    private static func referenceDataURL() -> String? {
        guard let f = currentReferenceFile(),
              let data = try? Data(contentsOf: f), !data.isEmpty else { return nil }
        return "data:" + referenceMIME() + ";base64," + data.base64EncodedString()
    }

    /// 参考音频上限（MiMo 的 base64 上限 10MB）
    static let maxReferenceBytes = 7_000_000

    // MARK: - 合成（整段一次，不重试）
    /// voice: voicedesign 时不用；内置音色时是音色 id；克隆时不用
    /// style: voicedesign 时是音色描述；内置音色/克隆时是风格指令
    static func synth(text: String,
                      voice: String,
                      style: String,
                      base: String,
                      apiKey: String,
                      model: String) async -> Data? {
        var root = base.trimmingCharacters(in: .whitespaces)
        while root.hasSuffix("/") { root.removeLast() }
        if root.hasSuffix("/chat/completions") { root = String(root.dropLast("/chat/completions".count)) }
        guard let url = URL(string: root + "/chat/completions") else {
            lastError = "地址不合法"
            return nil
        }

        let lower = model.lowercased()
        let isClone = lower.contains("voiceclone")
        let isDesign = lower.contains("voicedesign")

        // 缓存命中就不发请求
        let cacheVoice = isDesign ? style : voice
        if let hit = MiMoGuard.cached(text, voice: cacheVoice, style: style, model: model) {
            lastError = ""
            return hit
        }

        var messages: [[String: String]] = []
        var audioField: [String: Any] = ["format": "wav"]

        if isClone {
            guard let ref = referenceDataURL() else {
                lastError = "没有参考音频"
                return nil
            }
            // 克隆：只发 assistant，不传 user
            messages = [["role": "assistant", "content": text]]
            audioField["voice"] = ref
        } else if isDesign {
            // 设计：user = 音色描述，assistant = 要念的字；audio 不带 voice
            let desc: String
            if !style.trimmingCharacters(in: .whitespaces).isEmpty {
                desc = style
            } else {
                desc = isHot(text) ? MiMoVoice.defaultDescHot : MiMoVoice.defaultDescNormal
            }
            messages = [
                ["role": "user", "content": desc],
                ["role": "assistant", "content": text]
            ]
        } else {
            // 内置音色：voice 必须是那 9 个 id 之一
            let v = voice.trimmingCharacters(in: .whitespaces)
            audioField["voice"] = v.isEmpty ? "mimo_default" : v
            messages = [["role": "assistant", "content": text]]
            if !style.trimmingCharacters(in: .whitespaces).isEmpty {
                messages.insert(["role": "user", "content": style], at: 0)
            }
        }

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": false,
            "audio": audioField
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
            lastError = "请求体构造失败"
            return nil
        }

        await MiMoGuard.waitTurn()

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 55          // 和 aurabot 一致
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = payload

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                lastError = "无 HTTP 响应"
                return nil
            }
            guard (200..<300).contains(http.statusCode) else {
                var msg = "HTTP \(http.statusCode)"
                if let t = String(data: data, encoding: .utf8) {
                    let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { msg += "：" + String(trimmed.prefix(100)) }
                }
                lastError = msg
                return nil                 // 不重试，交给上层切本地
            }
            guard let audio = parseAudio(data), !audio.isEmpty else {
                lastError = "HTTP 200 但没返回音频"
                return nil
            }
            MiMoGuard.store(audio, text: text, voice: cacheVoice, style: style, model: model)
            lastError = ""
            return audio
        } catch {
            lastError = "网络异常：" + error.localizedDescription
            return nil
        }
    }

    /// 带硬超时的封装（界面用，防止极端情况转圈）
    static func synthWithTimeout(text: String,
                                 voice: String,
                                 style: String,
                                 base: String,
                                 apiKey: String,
                                 model: String,
                                 seconds: Double = 60) async -> Data? {
        await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                await synth(text: text, voice: voice, style: style,
                            base: base, apiKey: apiKey, model: model)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func parseAudio(_ data: Data) -> Data? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let audio = message["audio"] as? [String: Any],
              let b64 = audio["data"] as? String,
              let wav = Data(base64Encoded: b64) else { return nil }
        return wav
    }

    // MARK: - WAV 工具
    /// 把多段 16bit PCM WAV 拼成一段（克隆参考音频用）
    static func concatWAV(_ datas: [Data]) -> Data? {
        guard !datas.isEmpty else { return nil }
        if datas.count == 1 { return datas[0] }

        var pcm = Data()
        var headerTemplate: Data?
        for d in datas {
            guard let parsed = splitWAV(d) else { continue }
            headerTemplate = parsed.header
            pcm.append(parsed.pcm)
        }
        guard !pcm.isEmpty, var out = headerTemplate else { return nil }

        let total = UInt32(pcm.count)
        if out.count >= 44 {
            out.replaceSubrange(4..<8, with: withUnsafeBytes(of: (total + 36).littleEndian) { Data($0) })
            if let r = out.range(of: Data("data".utf8)) {
                let idx = r.lowerBound
                if idx + 8 <= out.count {
                    out.replaceSubrange((idx + 4)..<(idx + 8),
                                        with: withUnsafeBytes(of: total.littleEndian) { Data($0) })
                }
            }
        }
        out.append(pcm)
        return out
    }

    private struct WAVParts {
        var header: Data
        var pcm: Data
    }

    private static func splitWAV(_ d: Data) -> WAVParts? {
        guard d.count > 44,
              d.range(of: Data("RIFF".utf8))?.lowerBound == 0,
              let dataRange = d.range(of: Data("data".utf8)) else { return nil }
        let pcmStart = dataRange.lowerBound + 8
        guard pcmStart <= d.count else { return nil }
        return WAVParts(header: d.subdata(in: 0..<pcmStart), pcm: d.subdata(in: pcmStart..<d.count))
    }
}
