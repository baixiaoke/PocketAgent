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
    @State private var voices: [String] = ModelCatalog.builtinVoices
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

    var body: some View {
        Form {
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
                    Label("检测现有发音人", systemImage: "person.wave.2")
                }
                .disabled(busy)

                if let s = voiceStatus {
                    Text(s).font(.caption).foregroundStyle(s.hasPrefix("✅") ? .green : .orange)
                }

                Picker("当前音色", selection: $voice) {
                    if voices.isEmpty {
                        Text(voice.isEmpty ? "未设置" : voice).tag(voice)
                    }
                    ForEach(voices, id: \.self) { v in
                        Text(v).tag(v)
                    }
                }
            } header: {
                Text("发音人")
            } footer: {
                Text("会依次尝试 /voices、/audio/voices、/voice/list；服务端没有列表接口时列出内置常用音色。")
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

            Section {
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
                    Task { await doClone() }
                } label: {
                    HStack {
                        Label("上传并克隆", systemImage: "person.crop.circle.badge.plus")
                        Spacer()
                        if cloning { ProgressView() }
                    }
                }
                .disabled(cloning || audioURL == nil || cloneName.isEmpty)

                if let s = cloneStatus {
                    Text(s).font(.caption).foregroundStyle(s.hasPrefix("✅") ? .green : .orange)
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
        let (list, err) = await ModelCatalog.listVoices(base: base.isEmpty ? Store.shared.settings.baseURL : base,
                                                       apiKey: useKey)
        busy = false
        voices = list
        if let e = err {
            voiceStatus = "⚠️ \(e)"
        } else {
            voiceStatus = "✅ 服务端给出 \(list.count) 个音色"
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

        let (id, err) = await ModelCatalog.cloneVoice(
            base: base.isEmpty ? Store.shared.settings.baseURL : base,
            apiKey: useKey,
            name: cloneName,
            audio: data,
            filename: url.lastPathComponent)

        if let id = id {
            cloneStatus = "✅ 克隆提交成功：\(id)（可点上面的检测发音人刷新列表）"
            if id != "已提交" { voice = id; save() }
        } else {
            cloneStatus = "❌ \(err ?? "克隆失败")"
        }
    }

    private func save() {
        var s = Store.shared.settings
        s.ttsBaseURL = base.trimmingCharacters(in: .whitespaces)
        s.ttsModel = model.trimmingCharacters(in: .whitespaces)
        s.ttsAPIKey = key.trimmingCharacters(in: .whitespaces)
        s.ttsVoice = voice.trimmingCharacters(in: .whitespaces)
        Store.shared.saveSettings(s)
    }
}
