import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var baseURL = Store.shared.settings.baseURL
    @State private var model = Store.shared.settings.model
    @State private var apiKey = Store.shared.apiKey
    @State private var systemPrompt = Store.shared.settings.systemPrompt
    @State private var temperature = Store.shared.settings.temperature
    @State private var maxRounds = Store.shared.settings.maxRounds

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
                    HStack {
                        Text("温度")
                        Slider(value: $temperature, in: 0...1.5, step: 0.1)
                        Text(String(format: "%.1f", temperature)).font(.caption.monospaced())
                    }
                    Stepper("工具轮数上限：\(maxRounds)", value: $maxRounds, in: 1...20)
                } header: {
                    Text("行为")
                } footer: {
                    Text("轮数是一句话里最多连续调几次工具。调太多会烧 token，8 轮够日常用。")
                }

                Section("系统提示词（人设）") {
                    TextEditor(text: $systemPrompt)
                        .font(.callout)
                        .frame(minHeight: 160)
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
        Store.shared.saveSettings(s)
        Store.shared.saveAPIKey(apiKey)
    }

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
