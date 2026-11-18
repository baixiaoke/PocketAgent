import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var baseURL = Store.shared.settings.baseURL
    @State private var model = Store.shared.settings.model
    @State private var apiKey = Store.shared.apiKey
    @State private var systemPrompt = Store.shared.settings.systemPrompt
    @State private var temperature = Store.shared.settings.temperature
    @State private var maxRounds = Store.shared.settings.maxRounds
    @State private var requireApproval = Store.shared.settings.requireApproval
    @State private var autoSpeak = Store.shared.settings.autoSpeak
    @State private var speechRate = Store.shared.settings.speechRate
    @State private var agentName = Store.shared.settings.agentName
    @State private var userTitle = Store.shared.settings.userTitle
    @State private var tone = Store.shared.settings.tone
    @State private var companionMode = Store.shared.settings.companionMode
    @State private var unfilteredMode = Store.shared.settings.unfilteredMode
    @State private var autoExtractMemory = Store.shared.settings.autoExtractMemory
    @State private var careEnabled = Store.shared.settings.careEnabled
    @State private var careMorningHour = Store.shared.settings.careMorningHour
    @State private var careEveningHour = Store.shared.settings.careEveningHour
    @State private var autoModelSwitch = Store.shared.settings.autoModelSwitch
    @State private var reasoningModel = Store.shared.settings.reasoningModel
    @State private var imageBaseURL = Store.shared.settings.imageBaseURL
    @State private var imageModel = Store.shared.settings.imageModel
    @State private var imageAPIKey = Store.shared.settings.imageAPIKey
    @State private var imageSize = Store.shared.settings.imageSize
    @State private var ttsBaseURL = Store.shared.settings.ttsBaseURL
    @State private var ttsModel = Store.shared.settings.ttsModel
    @State private var ttsVoice = Store.shared.settings.ttsVoice
    @State private var ttsAPIKey = Store.shared.settings.ttsAPIKey
    @AppStorage("pa.requireBiometric") private var requireBiometric = false

    @State private var testing = false
    @State private var testResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://api.deepseek.com", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.callout.monospaced())
                    TextField("deepseek-chat", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                    SecureField("sk-…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                } header: {
                    Text("模型服务（OpenAI 兼容）")
                } footer: {
                    Text("baseURL 填到 /v1 或根路径都行，App 会自己拼 /chat/completions。Key 存在 Keychain，不进备份以外的任何地方。")
                }

                Section {
                    TextField("https://api.openai.com/v1", text: $imageBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.callout.monospaced())
                    TextField("dall-e-3 / flux / seedream…", text: $imageModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                    TextField("1024x1024", text: $imageSize)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                    TextField("API Key（留空复用上面那个）", text: $imageAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                } header: {
                    Text("图片生成")
                } footer: {
                    Text("留空 = 不启用。配好后直接说「画一张…」，生成的图会存进相册。")
                }

                Section {
                    TextField("https://api.openai.com/v1", text: $ttsBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.callout.monospaced())
                    TextField("tts-1 / cosyvoice…", text: $ttsModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                    TextField("音色，如 alloy", text: $ttsVoice)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                    TextField("API Key（留空复用上面那个）", text: $ttsAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                } header: {
                    Text("语音合成（TTS）")
                } footer: {
                    Text("留空 = 走系统本地语音：免费、离线、不用网。配了云端就用云端音色，失败自动退回本地。")
                }

                Section {
                    HStack {
                        Text("温度")
                        Slider(value: $temperature, in: 0...1.5, step: 0.1)
                        Text(String(format: "%.1f", temperature)).font(.caption.monospaced())
                    }
                    Stepper("工具轮数上限：\(maxRounds)", value: $maxRounds, in: 1...20)
                    Toggle("打开时用 Face ID 解锁", isOn: $requireBiometric)
                    Toggle("危险操作先问我", isOn: $requireApproval)
                    Toggle("回答自动念出来", isOn: $autoSpeak)
                    HStack {
                        Text("语速")
                        Slider(value: $speechRate, in: 0.35...0.6, step: 0.01)
                        Text(String(format: "%.2f", speechRate)).font(.caption.monospaced())
                    }
                } header: {
                    Text("行为")
                } footer: {
                    Text("「危险操作」= 写文件、建提醒、打开链接、发通知。开着更安全，关掉更快。")
                }

                Section {
                    TextField("小椒", text: $agentName)
                    TextField("主人", text: $userTitle)
                    Picker("语气", selection: $tone) {
                        ForEach(["温柔", "俏皮", "直接", "自然"], id: \.self) { Text($0) }
                    }
                    Toggle("情感陪伴模式", isOn: $companionMode)
                    Menu {
                        ForEach(PersonaPresets.all) { p in
                            Button {
                                PersonaStore.shared.apply(p)
                            } label: {
                                Label("\(p.title) · \(p.subtitle)", systemImage: p.icon)
                            }
                        }
                    } label: {
                        HStack {
                            Label("套用现成人格", systemImage: "wand.and.stars")
                            Spacer()
                            Text("\(PersonaPresets.all.count) 套")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle("无保留模式（破甲）", isOn: $unfilteredMode)
                        .onChange(of: unfilteredMode) { on in
                            if on { PersonaStore.shared.ensureUnfilteredSeeds() }
                        }
                    NavigationLink {
                        PersonaView()
                    } label: {
                        HStack {
                            Label("人格规则", systemImage: "person.text.rectangle")
                            Spacer()
                            Text("\(PersonaStore.shared.rules.count) 条")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("人设 / 陪伴")
                } footer: {
                    Text("开着会多留意你的情绪、主动问候；关掉就只办事不寒暄。")
                }

                Section("系统提示词（人设）") {
                    TextEditor(text: $systemPrompt)
                        .font(.callout)
                        .frame(minHeight: 160)
                }

                Section {
                    Toggle("每轮自动提炼记忆", isOn: $autoExtractMemory)                    Toggle("定时问候", isOn: $careEnabled)
                    if careEnabled {
                        Stepper("早上 \(careMorningHour):00", value: $careMorningHour, in: 5...11)
                        Stepper("晚上 \(careEveningHour):30", value: $careEveningHour, in: 18...23)
                    }
                    Toggle("长问题自动换推理模型", isOn: $autoModelSwitch)
                    if autoModelSwitch {
                        TextField("deepseek-reasoner", text: $reasoningModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.callout.monospaced())
                    }
                } header: {
                    Text("主动 / 自动化")
                } footer: {
                    Text("定时问候靠本地通知，不需要联网；关掉就不会再打扰。")
                }

                Section {
                    Button {
                        Task { await test() }
                    } label: {
                        HStack {
                            Text("测试连接")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(testing || apiKey.isEmpty)

                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(result.hasPrefix("✅") ? .green : .red)
                    }
                }

                Section {
                    NavigationLink("会话存储位置") {
                        InfoView()
                    }
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save(); dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        var s = Store.shared.settings
        s.baseURL = baseURL
        s.model = model
        s.systemPrompt = systemPrompt
        s.temperature = temperature
        s.maxRounds = maxRounds
        s.requireApproval = requireApproval
        s.autoSpeak = autoSpeak
        s.speechRate = speechRate
        s.agentName = agentName.isEmpty ? "小椒" : agentName
        s.userTitle = userTitle.isEmpty ? "主人" : userTitle
        s.tone = tone
        s.companionMode = companionMode
        s.unfilteredMode = unfilteredMode
        s.autoExtractMemory = autoExtractMemory
        s.careEnabled = careEnabled
        s.careMorningHour = careMorningHour
        s.careEveningHour = careEveningHour
        s.autoModelSwitch = autoModelSwitch
        s.reasoningModel = reasoningModel
        s.imageBaseURL = imageBaseURL.trimmingCharacters(in: .whitespaces)
        s.imageModel = imageModel.trimmingCharacters(in: .whitespaces)
        s.imageAPIKey = imageAPIKey.trimmingCharacters(in: .whitespaces)
        s.imageSize = imageSize.trimmingCharacters(in: .whitespaces).isEmpty ? "1024x1024" : imageSize
        s.ttsBaseURL = ttsBaseURL.trimmingCharacters(in: .whitespaces)
        s.ttsModel = ttsModel.trimmingCharacters(in: .whitespaces)
        s.ttsVoice = ttsVoice.trimmingCharacters(in: .whitespaces)
        s.ttsAPIKey = ttsAPIKey.trimmingCharacters(in: .whitespaces)
        Store.shared.saveSettings(s)
        Store.shared.saveAPIKey(apiKey)

        // 定时问候跟着设置走
        if careEnabled {
            Task {
                if await CareScheduler.requestPermission() {
                    CareScheduler.reschedule(settings: s)
                }
            }
        } else {
            CareScheduler.cancelAll()
        }    }

    private func test() async {
        testing = true
        testResult = nil
        defer { testing = false }

        var s = Store.shared.settings
        s.baseURL = baseURL
        s.model = model

        do {
            let turn = try await LLMClient().stream(
                settings: s,
                apiKey: apiKey,
                messages: [.user("只回复两个字：可用")],
                tools: [],
                onDelta: { _ in }
            )
            let answer = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            testResult = "✅ 通了：「\(answer.prefix(30))」"
        } catch {
            testResult = "❌ \(error.localizedDescription)"
        }
    }
}

struct InfoView: View {
    var body: some View {
        List {
            Section("会话数据") {
                Text(Store.shared.documentsDirectory.path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            Section("agent 能碰到的文件范围") {
                Text("只有上面这个 App 沙盒目录。系统相册、iCloud Drive、别的 App 的文件都碰不到——这是 iOS 的硬边界，不是没做。")
                    .font(.caption)
            }
            Section("用了哪些原生能力") {
                ForEach(["剪贴板", "本地通知", "提醒事项", "打开链接", "HTTP 请求", "沙盒文件读写"], id: \.self) {
                    Label($0, systemImage: "checkmark.seal")
                }
            }
        }
        .navigationTitle("关于数据")
    }
}

struct SessionsView: View {
    @EnvironmentObject private var rt: AgentRuntime
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(rt.sessions) { session in
                    Button {
                        rt.open(session)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.title).font(.callout).lineLimit(1)
                            Text("\(session.messages.count) 条 · \(session.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            rt.delete(session)
                        } label: { Label("删除", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle("会话")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        rt.newSession()
                        dismiss()
                    } label: { Image(systemName: "plus") }
                }
            }
        }
    }
}
