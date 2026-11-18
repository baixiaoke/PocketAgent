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
