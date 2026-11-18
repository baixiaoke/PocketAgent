import SwiftUI
import AVFoundation
import Speech

// MARK: - 引导文本
enum VoiceScript {
    static let lines: [String] = [
        "你好，很高兴认识你。今天天气不错，我们随便聊几句吧。",
        "我平时喜欢在晚上散步，一边走一边听音乐，脑子会安静下来。",
        "请把这句话读完整：早上八点半，从杭州东站出发，预计两小时四十分钟到达。",
        "有时候我也会累，会想找个人说说话，不用给建议，听着就好。",
        "最后一句：这是一段用于克隆声音的样本，读到这儿就差不多了。"
    ]

    /// 去掉标点空白，便于比对
    static func normalize(_ s: String) -> [Character] {
        let drop: Set<Character> = ["，", "。", "！", "？", "、", "；", "：", "「", "」", "（", "）", "\n", " "]
        return Array(s.filter { !drop.contains($0) })
    }

    /// 最长公共子序列比例，0…1
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = normalize(a), y = normalize(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        var dp = Array(repeating: Array(repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in 1...x.count {
            for j in 1...y.count {
                dp[i][j] = x[i-1] == y[j-1] ? dp[i-1][j-1] + 1 : max(dp[i-1][j], dp[i][j-1])
            }
        }
        return Double(dp[x.count][y.count]) / Double(max(x.count, y.count))
    }
}

// MARK: - 录音
@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    @Published var recording = false
    @Published var level: Float = 0
    @Published var seconds: Double = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var quietSince: Date?
    private var startedAt: Date?
    private var url: URL?

    /// 静音多久自动停
    var silenceStopAfter: TimeInterval = 1.6
    var onAutoStop: (() -> Void)?

    func requestPermission() async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { ok in c.resume(returning: ok) }
        }
    }

    func start() -> Bool {
        stopSilently()
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("voice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("seg-\(Int(Date().timeIntervalSince1970)).wav")

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVSampleRateKey: 24000,
                AVNumberOfChannelsKey: 1
            ]
            let r = try AVAudioRecorder(url: file, settings: settings)
            r.isMeteringEnabled = true
            r.record()
            recorder = r
            url = file
            recording = true
            seconds = 0
            startedAt = Date()
            quietSince = nil
            startTimer()
            return true
        } catch {
            recording = false
            return false
        }
    }

    func stop() -> URL? {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        recording = false
        level = 0
        return url
    }

    private func stopSilently() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        recording = false
        level = 0
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let rec = self.recorder, rec.isRecording else { return }
                rec.updateMeters()
                let db = rec.averagePower(forChannel: 0)
                // -60…0 → 0…1
                self.level = max(0, min(1, (db + 60) / 60))
                if let s = self.startedAt { self.seconds = Date().timeIntervalSince(s) }

                if db < -38 {
                    if self.quietSince == nil { self.quietSince = Date() }
                    else if let q = self.quietSince,
                            Date().timeIntervalSince(q) > self.silenceStopAfter,
                            self.seconds > 1.2 {
                        self.onAutoStop?()
                    }
                } else {
                    self.quietSince = nil
                }
            }
        }
    }
}

// MARK: - 整页流程
struct VoiceCloneView: View {
    @Environment(\.dismiss) private var dismiss

    let base: String
    let apiKey: String
    let onCloned: (String) -> Void

    @StateObject private var recorder = VoiceRecorder()

    @State private var step = 0
    @State private var clips: [URL] = []
    @State private var phase: Phase = .idle
    @State private var heard = ""
    @State private var score: Double = 0
    @State private var hint: String = ""
    @State private var voiceName = ""
    @State private var submitting = false
    @State private var finalMessage: String?

    enum Phase: Equatable {
        case idle          // 等开始
        case recording     // 正在录
        case checking      // 识别比对中
        case passed        // 这段过了
        case failed        // 没过，需要重录
        case allDone       // 全部念完，可以提交
    }

    private var currentLine: String {
        step < VoiceScript.lines.count ? VoiceScript.lines[step] : ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if phase == .allDone { finishCard } else { scriptCard }
                    recorderCard
                    if let m = finalMessage {
                        Text(m).font(.caption)
                            .foregroundStyle(m.hasPrefix("✅") ? .green : .orange)
                    }
                }
                .padding(16)
            }
            .background(PageBackground(page: .persona))
            .navigationTitle("录音克隆")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { recorder.stop(); dismiss() }
                }
            }
        }
        .onAppear { setup() }
        .onDisappear { _ = recorder.stop() }
    }

    // MARK: 组件
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("念 \(VoiceScript.lines.count) 段话，我给你做音色")
                .font(.headline).foregroundStyle(.white)
            Text("每段念完自动停下来，我会识别一遍看你念全没有。全部通过就能提交克隆。")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 6) {
                ForEach(0..<VoiceScript.lines.count, id: \.self) { i in
                    Capsule()
                        .fill(i < step ? Theme.mint : (i == step ? Theme.cyan : Color.white.opacity(0.15)))
                        .frame(height: 4)
                }
            }
            .padding(.top, 6)
        }
    }

    private var scriptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("第 \(step + 1) / \(VoiceScript.lines.count) 段")
                .font(.caption).foregroundStyle(Theme.cyan)
            Text(currentLine)
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)

            if !heard.isEmpty {
                Text("识别到：\(heard)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(3)
                HStack(spacing: 6) {
                    Text("相似度 \(Int(score * 100))%")
                        .font(.caption.monospaced())
                        .foregroundStyle(score > 0.6 ? Theme.mint : Theme.amber)
                    ProgressView(value: min(1, score)).tint(score > 0.6 ? Theme.mint : Theme.amber)
                }
            }

            if !hint.isEmpty {
                Text(hint).font(.caption).foregroundStyle(Theme.amber)
            }
        }
        .padding(16)
        .glassCard(radius: 18, tint: Theme.cyan)
    }

    private var recorderCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(phase == .recording ? Theme.danger.opacity(0.18) : Theme.cyan.opacity(0.10))
                    .frame(width: 150, height: 150)
                    .blur(radius: 18)
                Circle()
                    .fill(phase == .recording ? Theme.danger : Theme.cyan)
                    .frame(width: 96, height: 96)
                    .scaleEffect(1 + CGFloat(recorder.level) * 0.25)
                    .animation(.easeOut(duration: 0.1), value: recorder.level)
                    .overlay(
                        Image(systemName: phase == .recording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.black)
                    )
                    .onTapGesture { tap() }
            }
            .frame(maxWidth: .infinity)

            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.vertical, 8)
    }

    private var finishCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("五段都念完了")
                .font(.headline).foregroundStyle(.white)
            Text("给这个音色起个名字，然后提交。")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
            TextField("例如：我的声音", text: $voiceName)
                .textInputAutocapitalization(.never)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            Button {
                Task { await submit() }
            } label: {
                HStack {
                    Text(submitting ? "提交中…" : "提交克隆")
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(submitting || voiceName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(16)
        .glassCard(radius: 18, tint: Theme.mint)
    }

    private var statusText: String {
        switch phase {
        case .idle:      return "点一下开始念第 \(step + 1) 段"
        case .recording: return String(format: "正在录… %.1f 秒（停顿一下会自动停）", recorder.seconds)
        case .checking:  return "识别中…"
        case .passed:    return "这段过了，准备下一段"
        case .failed:    return "没听过关，再念一次"
        case .allDone:   return "全部完成"
        }
    }

    // MARK: 流程
    private func setup() {
        recorder.onAutoStop = { tap() }
    }

    private func tap() {
        switch phase {
        case .recording:
            guard let url = recorder.stop() else { return }
            phase = .checking
            Task { await verify(url) }
        case .idle, .failed, .passed:
            guard recorder.start() else {
                hint = "麦克风打不开，检查权限"
                return
            }
            phase = .recording
            heard = ""
            hint = ""
            score = 0
        case .checking, .allDone:
            break
        }
    }

    private func verify(_ url: URL) async {
        let text = await SpeechFileCheck.transcribe(url)
        heard = text
        score = VoiceScript.similarity(currentLine, text)

        if score >= 0.55 {
            clips.append(url)
            if step + 1 >= VoiceScript.lines.count {
                phase = .allDone
            } else {
                phase = .passed
                try? await Task.sleep(nanoseconds: 700_000_000)
                step += 1
                phase = .idle
            }
        } else {
            phase = .failed
            hint = score < 0.2 ? "几乎没识别到，检查麦克风权限或离远一点" : "念得和原文差得有点多，再念一次"
        }
    }

    private func submit() async {
        submitting = true
        defer { submitting = false }

        // 小米 MiMo：不需要上传，参考音频留在本地，用克隆模型时随请求发出去
        let isMiMo = MiMoVoice.looksLikeMiMo(model: Store.shared.settings.ttsModel,
                                             base: Store.shared.settings.ttsBaseURL)
        if isMiMo {
            let datas = clips.compactMap { try? Data(contentsOf: $0) }
            guard let ref = MiMoVoice.concatWAV(datas) else {
                finalMessage = "❌ 音频拼接失败"
                return
            }
            do {
                try MiMoVoice.saveReference(ref)
            } catch {
                finalMessage = "❌ 参考音频写不进沙盒"
                return
            }

            let model = "mimo-v2.5-tts-voiceclone"
            let probe = await MiMoVoice.synth(text: "你好，我是青露。",
                                             voice: "", style: voiceName,
                                             base: base,
                                             apiKey: apiKey,
                                             model: model)
            if probe != nil {
                var s = Store.shared.settings
                s.ttsBaseURL = base
                s.ttsModel = model
                s.ttsVoice = voiceName.isEmpty ? "克隆音色" : voiceName
                Store.shared.saveSettings(s)
                finalMessage = "✅ 参考音频已保存（\(ref.count / 1024) KB），克隆可用"
                onCloned("reference")
                try? await Task.sleep(nanoseconds: 900_000_000)
                dismiss()
            } else {
                finalMessage = "⚠️ 参考音频已存下（\(ref.count / 1024) KB），但试合成没成功——确认地址是 /v1、模型名是 mimo-v2.5-tts-voiceclone"
            }
            return
        }

        guard let merged = VoiceMerger.merge(clips) else {
            finalMessage = "❌ 音频合并失败"
            return
        }
        guard let data = try? Data(contentsOf: merged) else {
            finalMessage = "❌ 读不到合并后的音频"
            return
        }

        var probe = Store.shared.settings
        probe.ttsBaseURL = base
        probe.ttsAPIKey = ""

        let r = await ModelCatalog.cloneVoice(
            base: base, apiKey: apiKey,
            name: voiceName,
            audio: data,
            filename: "voice.m4a",
            format: .generic,
            settingsForVerify: probe,
            fallbackKey: apiKey)

        if let id = r.voiceID, r.verified {
            finalMessage = "✅ 克隆成功并验证通过：\(id)"
            onCloned(id)
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        } else if let id = r.voiceID {
            finalMessage = "⚠️ 提交了，但验证没过：\(id)\n\(r.log.suffix(240))"
        } else {
            finalMessage = "❌ 没成功\n\(r.log.suffix(300))"
        }
    }
}

// MARK: - 文件识别
enum SpeechFileCheck {
    static func transcribe(_ url: URL) async -> String {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        guard let recognizer, recognizer.isAvailable else { return "" }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false

        return await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
            var done = false
            recognizer.recognitionTask(with: request) { result, error in
                if done { return }
                if let r = result, r.isFinal {
                    done = true
                    c.resume(returning: r.bestTranscription.formattedString)
                } else if error != nil {
                    done = true
                    c.resume(returning: "")
                }
            }
            // 15 秒兜底
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                if !done { done = true; c.resume(returning: "") }
            }
        }
    }
}

// MARK: - 合并音频
enum VoiceMerger {
    static func merge(_ urls: [URL]) -> URL? {
        guard !urls.isEmpty else { return nil }
        let comp = AVMutableComposition()
        guard let track = comp.addMutableTrack(withMediaType: .audio,
                                               preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return nil
        }
        var cursor = CMTime.zero
        for url in urls {
            let asset = AVURLAsset(url: url)
            guard let src = asset.tracks(withMediaType: .audio).first else { continue }
            let range = CMTimeRange(start: .zero, duration: asset.duration)
            try? track.insertTimeRange(range, of: src, at: cursor)
            cursor = CMTimeAdd(cursor, asset.duration)
        }

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-merged-\(Int(Date().timeIntervalSince1970)).m4a")
        guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetAppleM4A) else {
            return nil
        }
        export.outputURL = out
        export.outputFileType = .m4a

        let sem = DispatchSemaphore(value: 0)
        export.exportAsynchronously { sem.signal() }
        sem.wait()
        return export.status == .completed ? out : nil
    }
}
