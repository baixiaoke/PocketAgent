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

    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    var rate: Float = 0.48
    var voiceIdentifier: String?

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String) {
        let clean = Self.stripMarkdown(text)
        guard !clean.isEmpty else { return }
        stop()
        let u = AVSpeechUtterance(string: String(clean.prefix(1200)))
        u.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier ?? "")
            ?? AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = rate
        u.pitchMultiplier = 1.0
        synth.speak(u)
        isSpeaking = true
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        player?.stop()
        player = nil
        isSpeaking = false
    }

    // MARK: - 云端 TTS（配了就走云端，没配就走系统语音）
    func speakSmart(_ text: String, settings: AgentSettings, fallbackKey: String) async {
        let clean = Self.stripMarkdown(text)
        guard !clean.isEmpty else { return }

        if !settings.ttsBaseURL.isEmpty, !settings.ttsModel.isEmpty {
            if let data = await Self.fetchSpeech(clean, settings: settings, fallbackKey: fallbackKey) {
                stop()
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                    try session.setActive(true)
                    let p = try AVAudioPlayer(data: data)
                    player = p
                    p.play()
                    isSpeaking = true
                    Task { @MainActor in
                        while let cur = self.player, cur.isPlaying {
                            try? await Task.sleep(nanoseconds: 200_000_000)
                        }
                        self.isSpeaking = false
                    }
                    return
                } catch {
                    // 云端播放失败，退回本地
                }
            }
        }
        speak(clean)
    }

    /// 调 OpenAI 兼容的 /audio/speech，返回音频数据
    static func fetchSpeech(_ text: String,
                            settings: AgentSettings,
                            fallbackKey: String) async -> Data? {
        let key = settings.ttsAPIKey.isEmpty ? fallbackKey : settings.ttsAPIKey

        // 小米 MiMo：走 chat/completions，音频在 message.audio.data
        if MiMoVoice.looksLikeMiMo(model: settings.ttsModel, base: settings.ttsBaseURL) {
            return await MiMoVoice.synth(text: text,
                                         instruction: settings.ttsVoice,
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
        t = t.replacingOccurrences(of: "```", with: " 代码块 ")
        for token in ["**", "##", "###", "`", "> ", "- "] {
            t = t.replacingOccurrences(of: token, with: "")
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
