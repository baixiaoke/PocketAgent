import SwiftUI
import Foundation

struct SpeechModelPage: View {
    @Environment(\.dismiss) private var dismiss

    @State private var base = Store.shared.settings.ttsBaseURL
    @State private var model = Store.shared.settings.ttsModel
    @State private var key = Store.shared.settings.ttsAPIKey
    @State private var voice = Store.shared.settings.ttsVoice
    @State private var style = Store.shared.settings.ttsStyle
    @State private var moodAffectsVoice = Store.shared.settings.moodAffectsVoice
    @State private var chunkLimit = Store.shared.settings.ttsChunkLimit
    @State private var cacheKB = MiMoGuard.cacheSize() / 1024

    @State private var models: [String] = []
    @State private var voices: [String] = []
    @State private var usingFallbackVoices = false
    @State private var status: String?
    @State private var voiceStatus: String?
    @State private var busy = false
    @State private var testing = false

    // 克隆
    @State private var cloneName = ""
    @State private var showAudioPicker = false
    @State private var audioURL: URL?
    @State private var cloneStatus: String?
    @State private var cloning = false
    @State private var cloneLog: String = ""
    @State private var cloneElapsed: Int = 0
    @State private var cloneFormat: ModelCatalog.CloneFormat = .generic

    /// 当前模型属于哪一类，决定页面显示什么
    enum Kind {
        case openAI        // 任意 OpenAI 兼容 /audio/speech
        case mimoBuiltin   // mimo-v2.5-tts：内置音色 + 风格指令
        case mimoDesign    // voicedesign：一段描述就是音色
        case mimoClone     // voiceclone：参考音频
    }

    private var kind: Kind {
        guard MiMoVoice.looksLikeMiMo(model: model, base: base) else { return .openAI }
        let m = model.lowercased()
        if m.contains("voiceclone") { return .mimoClone }
        if m.contains("voicedesign") { return .mimoDesign }
        return .mimoBuiltin
    }

    private var kindTitle: String {
        switch kind {
        case .openAI:      return "OpenAI 兼容 /audio/speech"
        case .mimoBuiltin: return "小米内置音色"
        case .mimoDesign:  return "小米文字设计音色"
        case .mimoClone:   return "小米声音克隆"
        }
    }

    /// 当前「音色」栏在这一类下叫什么、填什么
    private var voiceLabel: String {
        switch kind {
        case .openAI:      return "音色名（如 alloy）"
        case .mimoBuiltin: return "内置音色"
        case .mimoDesign:  return "音色描述"
        case .mimoClone:   return "备注名"
        }
    }

    var body: some View {
        Form {
            summarySection
            interfaceSection
            switch kind {
            case .mimoBuiltin: builtinSection
            case .mimoDesign:  designSection
            case .mimoClone:   cloneSection
            case .openAI:      openAISection
            }
            testSection
            if kind != .mimoDesign {
                moodSection
            }
        }
        .themedScroll(.settings)
        .navigationTitle("语音合成")
        .fileImporter(isPresented: $showAudioPicker, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { audioURL = url }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save(); dismiss() }.fontWeight(.semibold)
            }
        }
    }

    // MARK: 当前生效
    private var summarySection: some View {
        Section {
            LabeledContent("类型", value: kindTitle)
            LabeledContent("地址", value: base.isEmpty ? "未设" : base)
            LabeledContent("模型", value: model.isEmpty ? "未设（走本地语音）" : model)
            LabeledContent(voiceLabel, value: voice.isEmpty ? "未设" : voice)
            if kind == .mimoBuiltin || kind == .mimoClone {
                LabeledContent("风格", value: style.isEmpty ? "未设" : style)
            }
            if kind == .mimoClone, MiMoVoice.hasReference() {
                LabeledContent("参考音频",
                               value: "\(MiMoVoice.referenceSize() / 1024) KB · \(MiMoVoice.referenceMIME())")
            }
        } header: {
            Text("当前生效")
        } footer: {
            Text("下面只显示当前模型支持的项。换模型会自动变。")
        }
    }

    // MARK: 接口
    private var interfaceSection: some View {
        Section {
            TextField("https://api.xiaomimimo.com/v1", text: $base)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.URL).font(.callout.monospaced())
            TextField("API Key（留空用对话那个）", text: $key)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(.callout.monospaced())
            TextField("mimo-v2.5-tts", text: $model)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(.callout.monospaced())
            Button {
                Task { await detectModels() }
            } label: {
                HStack {
                    Label("检测可用模型", systemImage: "antenna.radiowaves.left.and.right")
                    Spacer()
                    if busy { ProgressView() }
                }
            }
            .disabled(busy)
            if !models.isEmpty {
                ForEach(models, id: \.self) { m in
                    Button {
                        model = m
                    } label: {
                        HStack {
                            Text(m).font(.caption.monospaced()).lineLimit(1)
                            Spacer()
                            if m == model {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.cyan)
                            }
                        }
                    }
                }
            }
            if let s = status {
                Text(s).font(.caption).foregroundStyle(s.hasPrefix("✅") ? .green : .orange)
            }
        } header: {
            Text("接口")
        } footer: {
            Text(modelHint)
        }
    }

    private var modelHint: String {
        switch kind {
        case .mimoBuiltin: return "mimo-v2.5-tts：用小米内置的 9 个音色，风格用一句话调语速语气。"
        case .mimoDesign:  return "mimo-v2.5-tts-voicedesign：不选音色，写一段描述，模型按描述造一个声音。"
        case .mimoClone:   return "mimo-v2.5-tts-voiceclone：用你的参考音频复刻声音，不需要选音色。"
        case .openAI:      return "任意 OpenAI 兼容的 /audio/speech 接口。"
        }
    }

    // MARK: 内置音色模型
    private var builtinSection: some View {
        Section {
            Picker("音色", selection: $voice) {
                ForEach(MiMoVoice.builtinVoiceIDs, id: \.self) { v in
                    Text(v).tag(v)
                }
            }
            TextField("风格，如：语速稍慢，语气轻快", text: $style)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Toggle("情绪影响朗读语气", isOn: $moodAffectsVoice)
        } header: {
            Text("音色与风格")
        } footer: {
            Text("音色固定 9 个（冰糖/茉莉/苏打/白桦/Mia/Chloe/Milo/Dean/default）。风格只调语速与语气，不改变嗓音。")
        }
    }

    // MARK: 设计音色模型
    private var designSection: some View {
        Section {
            TextEditor(text: $voice)
                .font(.callout)
                .frame(minHeight: 110)
            Menu {
                ForEach(Self.designExamples, id: \.self) { ex in
                    Button(ex) { voice = ex }
                }
            } label: {
                Label("套用示例描述", systemImage: "text.badge.plus")
            }
        } header: {
            Text("音色描述")
        } footer: {
            Text("写清：性别年龄 + 音色质地 + 情绪 + 语速。别写混响/回声这类后期词，也别写「普通」「标准」。")
        }
    }

    static let designExamples = [
        "温柔清亮的年轻女声，二十多岁，语速稍慢，听起来让人放松",
        "冷静克制的成熟女声，三十岁上下，音色偏冷，语速平稳",
        "活泼的少女音，音调偏高，语速快，尾音上扬",
        "低沉的成熟男声，四十岁左右，胸腔共鸣明显，语速慢",
        "略带沙哑的中性嗓音，语速中等，像在聊天不像播报"
    ]

    // MARK: 克隆模型
    @ViewBuilder
    private var cloneSection: some View {
        Section {
            HStack {
                Label("参考音频", systemImage: "waveform")
                Spacer()
                Text(MiMoVoice.hasReference()
                     ? "\(MiMoVoice.referenceSize() / 1024) KB"
                     : "还没有")
                    .font(.caption)
                    .foregroundStyle(MiMoVoice.hasReference() ? Theme.mint : .secondary)
            }
            if MiMoVoice.hasReference() {
                Button(role: .destructive) {
                    MiMoVoice.clearReference()
                } label: {
                    Label("清除参考音频", systemImage: "trash")
                }
            }
            NavigationLink {
                VoiceCloneView(base: base.isEmpty ? Store.shared.settings.ttsBaseURL : base,
                               apiKey: useKey,
                               onCloned: { id in voice = id; save() })
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "mic.badge.plus").foregroundStyle(Theme.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("跟着念，现场录一段")
                        Text("分 5 段引导录音，自动拼接成参考音频")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("参考音频")
        } footer: {
            Text("也可以从文件里选一段（mp3 / wav，10–60 秒干净人声，≤7 MB）。")
        }

        Section {
            TextField("音色备注名，如：我的声音", text: $cloneName)
            Button {
                showAudioPicker = true
            } label: {
                HStack {
                    Label(audioURL == nil ? "选择音频文件" : "已选：\(audioURL!.lastPathComponent)",
                          systemImage: "waveform.badge.plus")
                    Spacer()
                }
            }
            Button {
                if audioURL == nil {
                    cloneStatus = "先点上面「选择音频文件」"
                    return
                }
                if cloneName.trimmingCharacters(in: .whitespaces).isEmpty { cloneName = "我的音色" }
                Task { await doClone() }
            } label: {
                HStack {
                    Image(systemName: "person.crop.circle.badge.plus")
                    Text(cloning ? "上传中… \(cloneElapsed)s（45 秒超时）" : "上传并应用").fontWeight(.semibold)
                    Spacer()
                    if cloning { ProgressView() }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(cloning)

            if let s = cloneStatus {
                Text(s).font(.caption).foregroundStyle(s.hasPrefix("✅") ? .green : .orange)
            }
            if !cloneLog.isEmpty {
                Text(cloneLog).font(.caption2.monospaced())
                    .foregroundStyle(.secondary).textSelection(.enabled)
            }
        } header: {
            Text("从文件克隆")
        } footer: {
            Text("MiMo 的克隆不需要单独「创建音色」接口：这段参考音频会存在本地，每次合成时随请求发出去。")
        }
    }

    // MARK: OpenAI 兼容
    private var openAISection: some View {
        Section {
            TextField(voiceLabel, text: $voice)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(.callout.monospaced())
            Button {
                Task { await detectVoices() }
            } label: {
                Label("检测发音人", systemImage: "person.wave.2")
            }
            .disabled(busy)
            if !voices.isEmpty {
                Picker(usingFallbackVoices ? "内置音色（非服务端）" : "可选音色", selection: $voice) {
                    ForEach(voices, id: \.self) { v in Text(v).tag(v) }
                }
            }
            if let s = voiceStatus {
                Text(s).font(.caption).foregroundStyle(s.hasPrefix("✅") ? .green : .orange)
            }
            TextField("风格（可选）", text: $style)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
        } header: {
            Text("音色")
        } footer: {
            Text("服务端有音色列表就拉下来选；没有就手填。")
        }
    }

    // MARK: 试听
    private var testSection: some View {
        Section {
            Button {
                Task { await testVoice() }
            } label: {
                HStack {
                    Label("试听一句", systemImage: "play.circle")
                    Spacer()
                    if testing { ProgressView() }
                }
            }
            .disabled(testing)
            if let s = voiceStatus, kind != .openAI {
                Text(s).font(.caption2).foregroundStyle(.secondary)
            }
        } footer: {
            Text("用当前配置念一句短话，验证 Key、模型、音色是否都能用。")
        }
    }

    // MARK: 情绪
    @ViewBuilder
    private var moodSection: some View {
        Section {
            Toggle("情绪影响朗读语气", isOn: $moodAffectsVoice)
            Picker("分段长度", selection: $chunkLimit) {
                Text("短 150 字（出字快，请求多）").tag(150)
                Text("中 400 字").tag(400)
                Text("长 700 字（请求少，首字慢）").tag(700)
            }
        } footer: {
            Text("情绪只调语速节奏，不改嗓音。分段越长请求越少，越不容易被限流。")
        }

        Section {
            HStack {
                Label("语音缓存", systemImage: "internaldrive")
                Spacer()
                Text("\(cacheKB) KB")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
                MiMoGuard.clearCache()
                cacheKB = 0
            } label: {
                Label("清空缓存", systemImage: "trash")
            }
        } footer: {
            Text("同一句话第二次会直接播缓存，不再请求服务端——这是最省额度的一招。")
        }
    }

    // MARK: - 逻辑
    private var useKey: String { key.isEmpty ? Store.shared.apiKey : key }


    private func detectModels() async {
        busy = true
        status = nil
        let r = await ModelCatalog.listModels(base: base.isEmpty ? Store.shared.settings.baseURL : base,
                                              apiKey: useKey)
        busy = false
        if let e = r.error {
            status = "❌ \(e)"
            return
        }
        let ttsLike = r.models.filter {
            let l = $0.lowercased()
            return l.contains("tts") || l.contains("speech") || l.contains("audio")
        }
        models = ttsLike.isEmpty ? r.models : ttsLike
        status = "✅ 拉到 \(r.models.count) 个，语音相关 \(models.count) 个"
    }

    private func detectVoices() async {
        busy = true
        voiceStatus = nil
        let (list, err) = await ModelCatalog.listVoices(base: base.isEmpty ? Store.shared.settings.baseURL : base,
                                                       apiKey: useKey)
        busy = false
        if let e = err {
            usingFallbackVoices = true
            voices = list
            voiceStatus = "⚠️ \(e)"
        } else {
            usingFallbackVoices = false
            voices = list
            voiceStatus = "✅ 服务端返回 \(list.count) 个音色"
            if voice.isEmpty, let f = list.first { voice = f }
        }
    }

    private func testVoice() async {
        testing = true
        defer { testing = false }
        var s = Store.shared.settings
        s.ttsBaseURL = base
        s.ttsModel = model
        s.ttsAPIKey = key
        s.ttsVoice = voice
        s.ttsStyle = style
        s.moodAffectsVoice = moodAffectsVoice
        s.ttsChunkLimit = chunkLimit
        let data = await VoiceOut.fetchSpeech("你好，我是青露，现在在测试语音。",
                                             settings: s,
                                             fallbackKey: Store.shared.apiKey)
        if let d = data, !d.isEmpty {
            voiceStatus = "✅ 拿到音频 \(d.count) 字节，通话里听就是它"
        } else {
            voiceStatus = "❌ 没拿到音频：检查地址 / 模型 / Key / 音色"
        }
    }

    private func doClone() async {
        guard let url = audioURL else { return }
        cloning = true
        cloneStatus = nil
        defer { cloning = false }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            cloneStatus = "❌ 读不到音频文件（可能在 iCloud 没下载）"
            return
        }
        guard data.count > 44 else {
            cloneStatus = "❌ 这段音频太短或读不出来"
            return
        }
        guard data.count <= MiMoVoice.maxReferenceBytes else {
            cloneStatus = "❌ 音频太大（\(data.count / 1024 / 1024) MB），上限 7 MB"
            return
        }
        do {
            try MiMoVoice.saveReference(data)
        } catch {
            cloneStatus = "❌ 写不进沙盒"
            return
        }

        cloneElapsed = 0
        let timer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { cloneElapsed += 1 }
            }
        }
        let ok = await MiMoVoice.synthWithTimeout(text: "你好，我是青露。",
                                                  voice: "",
                                                  style: cloneName,
                                                  base: base.isEmpty ? Store.shared.settings.ttsBaseURL : base,
                                                  apiKey: useKey,
                                                  model: "mimo-v2.5-tts-voiceclone",
                                                  seconds: 45)
        timer.cancel()
        cloneLog = "参考音频 \(data.count / 1024) KB 已保存"

        if ok != nil {
            cloneStatus = "✅ 参考音频可用，克隆生效"
            var s = Store.shared.settings
            s.ttsBaseURL = base
            s.ttsModel = "mimo-v2.5-tts-voiceclone"
            s.ttsVoice = cloneName
            Store.shared.saveSettings(s)
            model = s.ttsModel
            voice = s.ttsVoice
        } else {
            cloneStatus = "⚠️ 已保存，但试合成没过（45 秒超时或服务端拒绝）。参考音频已留着"
        }
    }

    private func save() {
        var s = Store.shared.settings
        s.ttsBaseURL = base.trimmingCharacters(in: .whitespaces)
        s.ttsModel = model.trimmingCharacters(in: .whitespaces)
        s.ttsAPIKey = key.trimmingCharacters(in: .whitespaces)
        s.ttsVoice = voice.trimmingCharacters(in: .whitespaces)
        s.ttsStyle = style.trimmingCharacters(in: .whitespaces)
        s.moodAffectsVoice = moodAffectsVoice
        s.ttsChunkLimit = chunkLimit
        Store.shared.saveSettings(s)
    }
}
