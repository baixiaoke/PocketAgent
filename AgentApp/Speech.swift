import Foundation
import AVFoundation
import Speech

/// 语音输入：本地中文识别 + 自动断句。
/// 「语音审核」也在这里：识别结果先过一遍本地过滤，再决定要不要送进 agent。
@MainActor
final class SpeechEngine: NSObject, ObservableObject {

    @Published var transcript = ""
    @Published var isListening = false
    @Published var authorized = false
    @Published var errorText: String?
    @Published var level: Float = 0          // 0…1，给波形用

    /// 一句话说完（静音超时）时回调
    var onFinal: ((String) -> Void)?
    /// 边听边回调（输入框dictation用）
    var onPartial: ((String) -> Void)?
    /// true = 不做语音审核，原样回调（输入框听写用）
    var bypassReview = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private var silenceTimer: Timer?
    private var lastChange = Date()

    /// 静音多久算说完
    var silenceTimeout: TimeInterval = 1.8

    // MARK: - 权限
    func requestAuthorization() async -> Bool {
        let speechOK = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                c.resume(returning: status == .authorized)
            }
        }
        let micOK = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { ok in c.resume(returning: ok) }
        }
        authorized = speechOK && micOK
        if !authorized { errorText = "需要在设置里允许「语音识别」和「麦克风」" }
        return authorized
    }

    // MARK: - 开始 / 停止
    func start() {
        guard !isListening else { return }
        guard let recognizer, recognizer.isAvailable else {
            errorText = "这台设备的语音识别暂不可用"
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio,
                                    options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition {
                req.requiresOnDeviceRecognition = true    // 本地跑，不上传
            }
            request = req
            transcript = ""

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
                self?.updateLevel(buffer)
            }
            engine.prepare()
            try engine.start()

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                guard let self else { return }
                Task { @MainActor in
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        self.lastChange = Date()
                        self.onPartial?(self.transcript)
                        if result.isFinal { self.finishAndStop() }
                    }
                    if let error, self.isListening {
                        self.errorText = error.localizedDescription
                        self.finishAndStop()
                    }
                }
            }

            isListening = true
            errorText = nil
            lastChange = Date()
            startSilenceWatch()
        } catch {
            errorText = "麦克风启动失败：\(error.localizedDescription)"
        }
    }

    func stop() {
        guard isListening else { return }
        silenceTimer?.invalidate()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
        level = 0
    }

    private func finishAndStop() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        stop()
        if bypassReview {
            guard !text.isEmpty else { return }
            onFinal?(text)
            return
        }
        guard let reviewed = SpeechReview.review(text) else { return }   // ← 语音审核
        onFinal?(reviewed)
    }

    // MARK: - 静音检测
    private func startSilenceWatch() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.isListening else { return }
                if !self.transcript.isEmpty,
                   Date().timeIntervalSince(self.lastChange) > self.silenceTimeout {
                    self.finishAndStop()
                }
            }
        }
    }

    private func updateLevel(_ buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        for i in 0..<n { sum += abs(ch[i]) }
        let avg = sum / Float(n)
        Task { @MainActor in self.level = min(1, avg * 12) }
    }
}

/// 语音审核：把误识别、寒暄噪声、明显不是指令的东西挡在 agent 外面。
enum SpeechReview {
    private static let noise: Set<String> = [
        "", "嗯", "嗯嗯", "啊", "哦", "呃", "这个", "那个", "就是", "然后",
        "哈哈", "呵呵", "喂", "喂喂", "在吗", "在不在"
    ]

    /// 返回 nil = 这句话不送进模型
    static func review(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 去掉识别常见的句尾噪声
        for junk in ["。", "，", "、"] where s.count <= 2 {
            s = s.replacingOccurrences(of: junk, with: "")
        }
        guard !noise.contains(s) else { return nil }
        // 太短又不是明确指令（比如「停」「别」）就丢掉
        if s.count <= 1 { return nil }
        return s
    }
}

/// 语音输出：系统中文音色朗读，被打断能立刻闭嘴。
@MainActor
final class VoiceOut: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking = false
    /// 上一次念的来源：云端 / 本地（给界面显示用）
    @Published var lastSource: String = ""
    private var lastText: String = ""
    private var lastAt = Date.distantPast

    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    var rate: Float = 0.48
    var voiceIdentifier: String?

    override init() {
        super.init()
        synth.delegate = self
    }

    /// 固定一个中文音色，避免中途被系统换掉
    private func pinnedVoice() -> AVSpeechSynthesisVoice? {
        if let id = voiceIdentifier, let v = AVSpeechSynthesisVoice(identifier: id) {
            return v
        }
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("zh") }
        // 优先高质量（enhanced/premium），其次任意中文
        if let best = all.first(where: { $0.quality == .premium })
            ?? all.first(where: { $0.quality == .enhanced })
            ?? all.first {
            voiceIdentifier = best.identifier      // 记住它，下次仍用同一个
            return best
        }
        return AVSpeechSynthesisVoice(language: "zh-CN")
    }

    func speak(_ text: String) {
        let clean = Self.stripMarkdown(text)
        guard !clean.isEmpty else { return }
        stop()
        let voice = pinnedVoice()

        // 长文本按句切成 ≤700 字的小段，排队念完；同一个音色不变
        for chunk in Self.chunk(clean, limit: 700) {
            let u = AVSpeechUtterance(string: chunk)
            u.voice = voice
            u.rate = rate
            u.pitchMultiplier = 1.0
            synth.speak(u)
        }
        isSpeaking = true
    }

    /// 按句末标点切段，尽量不切断句子
    static func chunk(_ text: String, limit: Int) -> [String] {
        if text.count <= limit { return [text] }
        var out: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            let isEnd = ("。！？!?…\n" as String).contains(ch)
            if isEnd && current.count >= limit / 2 {
                out.append(current); current = ""
            } else if current.count >= limit {
                out.append(current); current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(current) }
        return out.isEmpty ? [text] : out
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        player?.stop()
        player = nil
        isSpeaking = false
    }

    /// 通话里语音识别占着会话，这里按优先级试几种，都能出声
    private func activateForPlayback() {
        let s = AVAudioSession.sharedInstance()
        do {
            try s.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try s.setActive(true)
        } catch {
            do {
                try s.setCategory(.playAndRecord, mode: .spokenAudio,
                                  options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
                try s.setActive(true)
            } catch {
                // 实在设不了就直接播，AVAudioPlayer 自己会去抢
            }
        }
    }

    // MARK: - 云端 TTS（配了就走云端，没配就走系统语音）
    func speakSmart(_ text: String, settings: AgentSettings, fallbackKey: String) async {
        let clean = Self.stripMarkdown(text)
        guard !clean.isEmpty else { return }

        // 同一条内容 3 秒内不重复念（通话页和聊天页可能同时触发）
        if clean == lastText, Date().timeIntervalSince(lastAt) < 3 {
            return
        }
        lastText = clean
        lastAt = Date()

        if !settings.ttsBaseURL.isEmpty, !settings.ttsModel.isEmpty {
            // 长文本一次合成容易超时或被截断，这里切成 ≤280 字再合成
            let pieces = Self.chunk(clean, limit: 280)
            if pieces.count > 1 {
                isSpeaking = true
                activateForPlayback()
                for piece in pieces {
                    if let data = await Self.fetchSpeech(piece, settings: settings, fallbackKey: fallbackKey),
                       let p = try? AVAudioPlayer(data: data) {
                        player = p
                        p.play()
                        let who = settings.ttsVoice.isEmpty ? settings.ttsModel : settings.ttsVoice
                        lastSource = "云端 · " + who
                        // 等这一段念完
                        var waited = 0.0
                        while p.isPlaying && waited < 90 {
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            waited += 0.2
                        }
                    } else {
                        lastSource = "中间一段没合成成功，已跳过"
                    }
                }
                isSpeaking = false
                return
            }

            if let data = await Self.fetchSpeech(clean, settings: settings, fallbackKey: fallbackKey) {
                stop()
                activateForPlayback()
                do {
                    let p = try AVAudioPlayer(data: data)
                    p.prepareToPlay()
                    player = p
                    p.play()
                    isSpeaking = true
                    let who = settings.ttsVoice.isEmpty ? settings.ttsModel : settings.ttsVoice
                    lastSource = "云端 · " + who
                    Task { @MainActor in
                        while let cur = self.player, cur.isPlaying {
                            try? await Task.sleep(nanoseconds: 200_000_000)
                        }
                        self.isSpeaking = false
                    }
                    return
                } catch {
                    lastSource = "云端音频播放失败：" + error.localizedDescription
                }
            } else if !settings.ttsBaseURL.isEmpty, !settings.ttsModel.isEmpty {
                lastSource = "云端没返回音频，已退回本地"
            }
        }
        lastSource = "本地系统语音"
        speak(clean)
    }

    /// 调 OpenAI 兼容的 /audio/speech，返回音频数据
    static func fetchSpeech(_ text: String,
                            settings: AgentSettings,
                            fallbackKey: String) async -> Data? {
        let key = settings.ttsAPIKey.isEmpty ? fallbackKey : settings.ttsAPIKey

        // 小米 MiMo：走 chat/completions，音频在 message.audio.data
        if MiMoVoice.looksLikeMiMo(model: settings.ttsModel, base: settings.ttsBaseURL) {
            let isDesign = settings.ttsModel.lowercased().contains("voicedesign")
            // 情绪只在开关打开时生效；voicedesign 的音色由描述决定，混进情绪会换嗓子
            let toward = (settings.moodAffectsVoice && !isDesign)
                ? MoodStore.shared.current.voiceStyle
                : ""
            let style = isDesign ? settings.ttsVoice : toward
            return await MiMoVoice.synth(text: text,
                                         voice: settings.ttsVoice,
                                         style: style,
                                         base: settings.ttsBaseURL,
                                         apiKey: key,
                                         model: settings.ttsModel)
        }

        var base = settings.ttsBaseURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        if !base.hasSuffix("/audio/speech") { base += "/audio/speech" }
        guard let url = URL(string: base) else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": settings.ttsModel,
            "input": String(text.prefix(2000)),
            "voice": settings.ttsVoice.isEmpty ? "alloy" : settings.ttsVoice,
            "response_format": "mp3"
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = payload

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              !data.isEmpty else { return nil }
        return data
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    /// 念之前先去掉 Markdown 标记，否则会把星号和井号念出来
    static func stripMarkdown(_ text: String) -> String {
        var t = text
        // 气泡分隔符不能让 TTS 看到：很多引擎把 | 当格式标记，读到就停
        t = t.replacingOccurrences(of: "|||", with: "。")
        t = t.replacingOccurrences(of: "|", with: "")
        t = t.replacingOccurrences(of: "```", with: " 代码块 ")
        for token in ["**", "##", "###", "`", "> ", "- "] {
            t = t.replacingOccurrences(of: token, with: "")
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
