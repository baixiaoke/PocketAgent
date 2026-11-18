import SwiftUI
import UniformTypeIdentifiers

// MARK: - 模型总览
struct ModelsView: View {
    private var store = Store.shared
    @State private var refresh = 0

    var body: some View {
        List {
            NavigationLink {
                ChatModelPage()
            } label: {
                row(icon: "bubble.left.and.bubble.right.fill",
                    title: "对话模型",
                    value: store.settings.model.isEmpty ? "未设置" : store.settings.model,
                    sub: store.settings.baseURL)
            }

            NavigationLink {
                ImageModelPage()
            } label: {
                row(icon: "photo.on.rectangle.angled",
                    title: "图片生成",
                    value: store.settings.imageModel.isEmpty ? "未启用" : store.settings.imageModel,
                    sub: store.settings.imageBaseURL)
            }

            NavigationLink {
                SpeechModelPage()
            } label: {
                row(icon: "waveform",
                    title: "语音合成",
                    value: store.settings.ttsModel.isEmpty ? "本地系统语音" : store.settings.ttsModel,
                    sub: store.settings.ttsBaseURL)
            }
        }
        .themedScroll(.settings)
        .navigationTitle("模型")
        .id(refresh)
        .onAppear { refresh += 1 }
    }

    private func row(icon: String, title: String, value: String, sub: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Theme.cyan)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.medium))
                Text(value).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !sub.isEmpty {
                    Text(sub).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 可点的模型行
private struct ModelChooser: View {
    let models: [String]
    @Binding var selected: String

    var body: some View {
        if models.isEmpty {
            Text("还没检测，点上面的按钮拉一下列表")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(models, id: \.self) { m in
                Button {
                    selected = m
                } label: {
                    HStack {
                        Text(m).font(.callout.monospaced()).lineLimit(1)
                        Spacer()
                        if m == selected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.cyan)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 对话模型
struct ChatModelPage: View {
    @Environment(\.dismiss) private var dismiss

    @State private var base = Store.shared.settings.baseURL
    @State private var model = Store.shared.settings.model
    @State private var key = Store.shared.apiKey

    @State private var models: [String] = []
    @State private var status: String?
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                TextField("https://api.deepseek.com", text: $base)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL).font(.callout.monospaced())
                TextField("sk-…", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.callout.monospaced())
                TextField("deepseek-chat", text: $model)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.callout.monospaced())
            } header: {
                Text("接口")
            }

            Section {
                Button {
                    Task { await detect() }
                } label: {
                    HStack {
                        Label("检测可用模型", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        if busy { ProgressView() }
                    }
                }
                .disabled(busy || key.isEmpty)

                if let s = status {
                    Text(s).font(.caption).foregroundStyle(s.hasPrefix("✅") ? .green : .orange)
                }
            } footer: {
                Text("会请求一次 /v1/models，把服务端列出来的模型拉回来点选。")
            }

            Section("可选模型") {
                ModelChooser(models: models, selected: $model)
            }
        }
        .navigationTitle("对话模型")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save(); dismiss() }.fontWeight(.semibold)
            }
        }
    }

    private func detect() async {
        busy = true
        status = nil
        let r = await ModelCatalog.listModels(base: base, apiKey: key)
        busy = false
        models = r.models
        if let e = r.error {
            status = "❌ \(e)"
        } else {
            status = "✅ 拉到 \(r.models.count) 个模型"
            if let first = r.models.first(where: { $0.lowercased().contains("chat") }) ?? r.models.first {
                if model.isEmpty { model = first }
            }
        }
    }

    private func save() {
        var s = Store.shared.settings
        s.baseURL = base.trimmingCharacters(in: .whitespaces)
        s.model = model.trimmingCharacters(in: .whitespaces)
        Store.shared.saveSettings(s)
        Store.shared.saveAPIKey(key.trimmingCharacters(in: .whitespaces))
    }
}

// MARK: - 图片模型
struct ImageModelPage: View {
    @Environment(\.dismiss) private var dismiss

    @State private var base = Store.shared.settings.imageBaseURL
    @State private var model = Store.shared.settings.imageModel
    @State private var key = Store.shared.settings.imageAPIKey
    @State private var size = Store.shared.settings.imageSize

    @State private var models: [String] = []
    @State private var status: String?
    @State private var busy = false

    var body: some View {
        Form {

            Section {
                TextField("https://api.openai.com/v1", text: $base)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL).font(.callout.monospaced())
                TextField("API Key（留空用对话那个）", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.callout.monospaced())
                TextField("dall-e-3", text: $model)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.callout.monospaced())
                TextField("1024x1024", text: $size)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.callout.monospaced())
            } header: {
                Text("图片接口")
            } footer: {
                Text("留空 = 不启用。生成的图会存进相册，并显示在聊天里。")
            }

            Section {
                Button {
                    Task { await detect() }
                } label: {
                    HStack {
                        Label("检测可用模型", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        if busy { ProgressView() }
                    }
                }
                .disabled(busy || base.isEmpty)

                if let s = status {
                    Text(s).font(.caption).foregroundStyle(s.hasPrefix("✅") ? .green : .orange)
                }
            } footer: {
                Text("会拉 /v1/models，并优先列出名字里带 image / dall / flux / sd / seedream 的。")
            }

            Section("可选模型") {
                ModelChooser(models: models, selected: $model)
            }
        }
        .navigationTitle("图片生成")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save(); dismiss() }.fontWeight(.semibold)
            }
        }
    }

    private func detect() async {
        busy = true
        status = nil
        let useKey = key.isEmpty ? Store.shared.apiKey : key
        let r = await ModelCatalog.listModels(base: base, apiKey: useKey)
        busy = false
        if let e = r.error {
            status = "❌ \(e)"
            return
        }
        let imageLike = r.models.filter { m in
            let l = m.lowercased()
            return l.contains("image") || l.contains("dall") || l.contains("flux")
                || l.contains("sd") || l.contains("seedream") || l.contains("imagen")
        }
        models = imageLike.isEmpty ? r.models : imageLike
        status = "✅ 拉到 \(r.models.count) 个，其中图片相关 \(models.count) 个"
    }

    private func save() {
        var s = Store.shared.settings
        s.imageBaseURL = base.trimmingCharacters(in: .whitespaces)
        s.imageModel = model.trimmingCharacters(in: .whitespaces)
        s.imageAPIKey = key.trimmingCharacters(in: .whitespaces)
        s.imageSize = size.trimmingCharacters(in: .whitespaces).isEmpty ? "1024x1024" : size
        Store.shared.saveSettings(s)
    }
}

// MARK: - 语音模型
struct SpeechModelPage: View {
    @Environment(\.dismiss) private var dismiss

    @State private var base = Store.shared.settings.ttsBaseURL
    @State private var model = Store.shared.settings.ttsModel
    @State private var key = Store.shared.settings.ttsAPIKey
    @State private var voice = Store.shared.settings.ttsVoice

    @State private var models: [String] = []
    @State private var voices: [String] = []
    @State private var moodAffectsVoice = Store.shared.settings.moodAffectsVoice
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
    @State private var cloneLog: String = ""
    @State private var cloneFormat: ModelCatalog.CloneFormat = .generic
    @State private var cloning = false

    var body: some View {
        Form {
            Section {
                LabeledContent("地址", value: base.isEmpty ? "未设" : base)
                LabeledContent("模型", value: model.isEmpty ? "未设（走本地语音）" : model)
                LabeledContent("音色", value: voice.isEmpty ? "未设" : voice)
                if MiMoVoice.hasReference() {
                    LabeledContent("参考音频",
                                   value: "\(MiMoVoice.referenceSize() / 1024) KB · \(MiMoVoice.referenceMIME())")
                }
                Toggle("情绪影响朗读语气", isOn: $moodAffectsVoice)
            } header: {
                Text("当前生效")
            } footer: {
                Text("改动要点右上角「保存」，或者用下面克隆区的「保存并生效」。情绪默认不影响音色；打开开关只会调语速和节奏。")
            }

            Section {
                TextField("https://api.openai.com/v1", text: $base)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL).font(.callout.monospaced())
                TextField("API Key（留空用对话那个）", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.callout.monospaced())
                TextField("tts-1", text: $model)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.callout.monospaced())
            } header: {
                Text("语音接口")
            } footer: {
                Text("全部留空 = 走系统本地语音（免费、离线）。填了优先用云端，失败自动回退本地。")
            }

            Section {
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
                if let s = status {
                    Text(s).font(.caption).foregroundStyle(s.hasPrefix("✅") ? .green : .orange)
                }
            }

            Section("可选模型") {
                ModelChooser(models: models, selected: $model)
            }

            Section {
                Button {
                    Task { await detectVoices() }
                } label: {
                    Label("检测服务端发音人", systemImage: "person.wave.2")
                }
                .disabled(busy)

                if let s = voiceStatus {
                    Text(s).font(.caption).foregroundStyle(s.hasPrefix("✅") ? .green : .orange)
                }

                if !voices.isEmpty {
                    Picker(usingFallbackVoices ? "内置音色（非服务端）" : "当前音色", selection: $voice) {
                        ForEach(voices, id: \.self) { v in
                            Text(v).tag(v)
                        }
                    }
                }

                if voices.isEmpty {
                    TextField("音色名或描述（MiMo 填描述，如：温柔清亮的年轻女声）", text: $voice)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                }
            } header: {
                Text("发音人")
            } footer: {
                Text("只认真的服务端列表。拉不到就明确告诉你不支持，再给你一份内置常用名单，但那不是「检测出来的」。")
            }

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
            } footer: {
                Text("会用当前模型和音色念一句短话，验证 Key、模型、音色是否都能用。")
            }

            if MiMoVoice.looksLikeMiMo(model: model, base: base) {
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
                } header: {
                    Text("小米 MiMo")
                } footer: {
                    Text("三个模型分工：mimo-v2.5-tts = 用内置音色（mimo_default / 冰糖 / 茉莉 / 苏打 / 白桦 / Mia / Chloe / Milo / Dean）；mimo-v2.5-tts-voicedesign = 「音色」那栏写描述，自动造声音；mimo-v2.5-tts-voiceclone = 用上面的参考音频克隆。参考音频只在本地，随请求发出去。")
                }
            }

            Section {
                NavigationLink {
                    VoiceCloneView(base: base.isEmpty ? Store.shared.settings.baseURL : base,
                                   apiKey: useKey,
                                   onCloned: { id in
                                       voice = id
                                       save()
                                   })
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mic.badge.plus")
                            .foregroundStyle(Theme.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("跟着念，现场录一段")
                            Text("分 5 段引导录音，识别校验后自动合并提交")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Picker("接口格式", selection: $cloneFormat) {
                    ForEach(ModelCatalog.CloneFormat.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                TextField("克隆音色名字（如：我的声音）", text: $cloneName)
                Button {
                    showAudioPicker = true
                } label: {
                    HStack {
                        Label(audioURL == nil ? "选择一段音频样本" : "已选：\(audioURL!.lastPathComponent)",
                              systemImage: "waveform.badge.plus")
                        Spacer()
                    }
                }
                Button {
                    if audioURL == nil {
                        cloneStatus = "先点上面「选择一段音频样本」，选好再来"
                        return
                    }
                    if cloneName.trimmingCharacters(in: .whitespaces).isEmpty {
                        cloneName = "我的音色"
                    }
                    Task { await doClone() }
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.plus")
                        Text(cloning ? "上传中…" : "上传并克隆").fontWeight(.semibold)
                        Spacer()
                        if cloning { ProgressView() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(cloning)

                if audioURL == nil {
                    Text("① 先选音频　② 起个名字　③ 点上传并克隆")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let s = cloneStatus {
                    Text(s).font(.caption).foregroundStyle(s.hasPrefix("✅") ? .green : .orange)
                }

                Button {
                    save()
                    cloneStatus = "✅ 已保存：模型 \(model.isEmpty ? "未设" : model) · 音色 \(voice.isEmpty ? "未设" : voice)"
                } label: {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                        Text("保存并生效").fontWeight(.semibold)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)

                if !cloneLog.isEmpty {
                    Text(cloneLog)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("声音克隆")
            } footer: {
                Text("按最常见的 /voices/add（multipart，字段 name + files）提交。不同厂商字段不同，失败会显示服务端原话。建议 10–60 秒干净人声。")
            }
        }
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
        let ttsLike = r.models.filter { $0.lowercased().contains("tts") || $0.lowercased().contains("speech") }
        models = ttsLike.isEmpty ? r.models : ttsLike
        status = "✅ 拉到 \(r.models.count) 个，语音相关 \(models.count) 个"
    }

    private func detectVoices() async {
        busy = true
        voiceStatus = nil

        // 小米 MiMo 没有音色列表接口：音色 = 一段文字描述（voicedesign）或参考音频（voiceclone）
        if MiMoVoice.looksLikeMiMo(model: model, base: base) {
            busy = false
            voices = MiMoVoice.builtinVoiceIDs
            usingFallbackVoices = false
            if model.lowercased().contains("voicedesign") {
                voiceStatus = "ℹ️ 当前是 voicedesign 模型：不支持内置音色，这栏写音色描述"
            } else if model.lowercased().contains("voiceclone") {
                voiceStatus = "ℹ️ 当前是 voiceclone 模型：音色来自参考音频，这栏只作备注"
            } else {
                voiceStatus = "✅ 小米内置音色 9 个（mimo-v2.5-tts 可用）"
            }
            return
        }

        let (list, err) = await ModelCatalog.listVoices(base: base.isEmpty ? Store.shared.settings.baseURL : base,
                                                       apiKey: useKey)
        busy = false

        if let e = err {
            // 服务端没有音色接口：给内置名单，但明确标注
            usingFallbackVoices = true
            voices = list
            voiceStatus = "⚠️ \(e)（下面是内置名单，不是这个服务给你的）"
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
        let data = await VoiceOut.fetchSpeech("你好，我是青露，现在在测试语音。", settings: s, fallbackKey: Store.shared.apiKey)
        if data == nil {
            voiceStatus = "❌ 没拿到音频，检查地址 / 模型 / Key / 音色"
        } else {
            voiceStatus = "✅ 拿到音频 \(data!.count) 字节，点通话就能听到"
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
            cloneStatus = "❌ 读不到音频文件"
            return
        }

        // 小米 MiMo：不走 multipart 上传，参考音频直接存在本地
        if MiMoVoice.looksLikeMiMo(model: model, base: base) {
            guard data.count > 44 else {
                cloneStatus = "❌ 这段音频太短或读不出来"
                return
            }
            do {
                try MiMoVoice.saveReference(data)
            } catch {
                cloneStatus = "❌ 写不进沙盒"
                return
            }
            let ok = await MiMoVoice.synth(text: "你好，我是青露。",
                                           voice: "", style: cloneName,
                                           base: base.isEmpty ? Store.shared.settings.ttsBaseURL : base,
                                           apiKey: useKey,
                                           model: "mimo-v2.5-tts-voiceclone")
            cloneLog = "参考音频 \(data.count / 1024) KB 已保存"
            if ok != nil {
                cloneStatus = "✅ 参考音频可用，克隆生效"
                var s = Store.shared.settings
                s.ttsBaseURL = base
                s.ttsModel = "mimo-v2.5-tts-voiceclone"
                s.ttsVoice = cloneName.isEmpty ? "克隆音色" : cloneName
                Store.shared.saveSettings(s)
                model = s.ttsModel
                voice = s.ttsVoice
            } else {
                cloneStatus = "⚠️ 已保存，但试合成没成功（检查地址 /v1、模型名）"
            }
            return
        }

        var probe = Store.shared.settings
        probe.ttsBaseURL = base
        probe.ttsModel = model
        probe.ttsAPIKey = key

        let r = await ModelCatalog.cloneVoice(
            base: base.isEmpty ? Store.shared.settings.baseURL : base,
            apiKey: useKey,
            name: cloneName,
            audio: data,
            filename: url.lastPathComponent,
            format: cloneFormat,
            settingsForVerify: probe,
            fallbackKey: Store.shared.apiKey)

        cloneLog = r.log

        if let id = r.voiceID {
            if r.verified {
                cloneStatus = "✅ 克隆成功并验证通过：\(id)"
                voice = id
                save()
            } else {
                cloneStatus = "⚠️ 提交成功但验证没过：\(id)（先看下面的服务端原话）"
            }
        } else {
            cloneStatus = "❌ 没成功，看下面的服务端原话"
        }
    }

    private func save() {
        var s = Store.shared.settings
        s.ttsBaseURL = base.trimmingCharacters(in: .whitespaces)
        s.ttsModel = model.trimmingCharacters(in: .whitespaces)
        s.ttsAPIKey = key.trimmingCharacters(in: .whitespaces)
        s.ttsVoice = voice.trimmingCharacters(in: .whitespaces)
        s.moodAffectsVoice = moodAffectsVoice
        Store.shared.saveSettings(s)
    }
}
