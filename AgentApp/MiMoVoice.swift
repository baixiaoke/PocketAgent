import Foundation

/// 小米 MiMo 的语音：走 /chat/completions，音频在 message.audio.data（base64 WAV）
enum MiMoVoice {

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

    static func hasReference() -> Bool {
        FileManager.default.fileExists(atPath: referenceURL.path)
    }

    static func referenceSize() -> Int {
        (try? Data(contentsOf: referenceURL).count) ?? 0
    }

    static func saveReference(_ data: Data) throws {
        try data.write(to: referenceURL, options: .atomic)
    }

    static func clearReference() {
        try? FileManager.default.removeItem(at: referenceURL)
    }

    private static func referenceDataURL() -> String? {
        guard let data = try? Data(contentsOf: referenceURL), !data.isEmpty else { return nil }
        return "data:audio/wav;base64," + data.base64EncodedString()
    }

    // MARK: - 合成
    /// text: 要念的文本；instruction: 音色描述（voicedesign 用）
    static func synth(text: String,
                      instruction: String,
                      base: String,
                      apiKey: String,
                      model: String) async -> Data? {
        var root = base.trimmingCharacters(in: .whitespaces)
        while root.hasSuffix("/") { root.removeLast() }
        if root.hasSuffix("/chat/completions") { root = String(root.dropLast("/chat/completions".count)) }
        guard let url = URL(string: root + "/chat/completions") else { return nil }

        let isClone = model.lowercased().contains("voiceclone")
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "assistant", "content": text],
                ["role": "user", "content": instruction.isEmpty ? "自然、清楚的中文女声" : instruction]
            ],
            "stream": false
        ]

        if isClone {
            guard let ref = referenceDataURL() else { return nil }
            body["audio"] = ["voice": ref]
        }

        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = payload

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }

        return parseAudio(data)
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
    /// 把多段 16bit PCM WAV 拼成一段（只处理同采样率同声道）
    static func concatWAV(_ datas: [Data]) -> Data? {
        guard !datas.isEmpty else { return nil }
        if datas.count == 1 { return datas[0] }

        var pcm = Data()
        var sampleRate: UInt32 = 24000
        var channels: UInt16 = 1
        var bits: UInt16 = 16
        var headerTemplate: Data?

        for d in datas {
            guard let parsed = splitWAV(d) else { continue }
            sampleRate = parsed.sampleRate
            channels = parsed.channels
            bits = parsed.bits
            headerTemplate = parsed.header
            pcm.append(parsed.pcm)
        }
        guard !pcm.isEmpty, let tpl = headerTemplate else { return nil }

        var out = tpl
        // 修正 RIFF 与 data 长度
        let total = UInt32(pcm.count)
        if out.count >= 44 {
            let riffSize = total + 36
            out.replaceSubrange(4..<8, with: withUnsafeBytes(of: riffSize.littleEndian) { Data($0) })
            let dataSize = total
            // 找 "data" 标记
            if let r = out.range(of: Data("data".utf8)) {
                let idx = r.lowerBound
                if idx + 8 <= out.count {
                    out.replaceSubrange((idx + 4)..<(idx + 8),
                                        with: withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
                }
            }
        }
        out.append(pcm)
        _ = (sampleRate, channels, bits)
        return out
    }

    private struct WAVParts {
        var header: Data
        var pcm: Data
        var sampleRate: UInt32
        var channels: UInt16
        var bits: UInt16
    }

    private static func splitWAV(_ d: Data) -> WAVParts? {
        guard d.count > 44,
              let riff = d.range(of: Data("RIFF".utf8)),
              riff.lowerBound == 0,
              let fmt = d.range(of: Data("fmt ".utf8)),
              let dataRange = d.range(of: Data("data".utf8)) else { return nil }

        let fmtStart = fmt.lowerBound
        func u16(_ off: Int) -> UInt16 {
            guard off + 2 <= d.count else { return 0 }
            return d.subdata(in: off..<(off + 2)).withUnsafeBytes { $0.load(as: UInt16.self) }
        }
        func u32(_ off: Int) -> UInt32 {
            guard off + 4 <= d.count else { return 0 }
            return d.subdata(in: off..<(off + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }
        }

        let channels = u16(fmtStart + 10)
        let sampleRate = u32(fmtStart + 12)
        let bits = u16(fmtStart + 22)

        let pcmStart = dataRange.lowerBound + 8
        guard pcmStart <= d.count else { return nil }
        let pcm = d.subdata(in: pcmStart..<d.count)
        let header = d.subdata(in: 0..<pcmStart)
        return WAVParts(header: header, pcm: pcm, sampleRate: sampleRate, channels: channels, bits: bits)
    }
}
