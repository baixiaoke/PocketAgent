import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    // 人设 / 行为
    @State private var temperature = Store.shared.settings.temperature
    @State private var maxRounds = Store.shared.settings.maxRounds
    @State private var requireApproval = Store.shared.settings.requireApproval
    @State private var autoSpeak = Store.shared.settings.autoSpeak
    @State private var replyAsVoice = Store.shared.settings.replyAsVoice
    @State private var speechRate = Store.shared.settings.speechRate
    @State private var agentName = Store.shared.settings.agentName
    @State private var userTitle = Store.shared.settings.userTitle
    @State private var tone = Store.shared.settings.tone
    @State private var companionMode = Store.shared.settings.companionMode
    @State private var unfilteredMode = Store.shared.settings.unfilteredMode
    @State private var unfilteredLevel = Store.shared.settings.unfilteredLevel

    // 主动 / 自动化
    @State private var autoExtractMemory = Store.shared.settings.autoExtractMemory
    @State private var careEnabled = Store.shared.settings.careEnabled
    @State private var morningTime = SettingsView.makeTime(Store.shared.settings.careMorningHour,
                                                          Store.shared.settings.careMorningMinute)
    @State private var eveningTime = SettingsView.makeTime(Store.shared.settings.careEveningHour,
                                                          Store.shared.settings.careEveningMinute)

    static func makeTime(_ hour: Int, _ minute: Int) -> Date {
        var c = DateComponents()
        c.hour = hour
        c.minute = minute
        return Calendar.current.date(from: c) ?? Date()
    }
    @State private var autoModelSwitch = Store.shared.settings.autoModelSwitch
    @State private var reasoningModel = Store.shared.settings.reasoningModel

    @AppStorage("pa.requireBiometric") private var requireBiometric = false
    @AppStorage("pa.theme") private var themeRaw = "dark"
    @AppStorage("pa.fontScale") private var fontRaw = FontScale.normal.rawValue

    @State private var showRestore = false
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var restoreMessage: String?
    @State private var careInfo: String?
    @State private var careTesting = false
    @State private var showBgPicker = false
    @State private var pickingPage: ThemeManager.Page = .chat
    @State private var pickedBg: PhotosPickerItem?
    @ObservedObject private var themeMgr = ThemeManager.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        ModelsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "cpu")
                                .foregroundStyle(Theme.cyan)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("模型与接口")
                                Text("对话 · 图片 · 语音")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text("三个模型分开配：对话、图片生成、语音合成。每页都能一键检测服务端有哪些可用模型。")
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
                    Toggle("回复显示成语音条（点一下才播）", isOn: $replyAsVoice)
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
                    TextField("青露", text: $agentName)
                    TextField("主人", text: $userTitle)
                    Picker("语气", selection: $tone) {
                        ForEach(["温柔", "俏皮", "直接", "自然"], id: \.self) { Text($0) }
                    }
                    Toggle("情感陪伴模式", isOn: $companionMode)
                    Toggle("无保留模式（破甲）", isOn: $unfilteredMode)
                        .onChange(of: unfilteredMode) { on in
                            if on { PersonaStore.shared.ensureUnfilteredSeeds() }
                        }
                    if unfilteredMode {
                        Picker("破甲强度", selection: $unfilteredLevel) {
                            Text("标准").tag(1)
                            Text("强").tag(2)
                            Text("极强").tag(3)
                        }
                        .pickerStyle(.segmented)
                    }
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
                    NavigationLink {
                        PromptInspectorView()
                    } label: {
                        Label("查看实际提示词", systemImage: "doc.text.magnifyingglass")
                    }
                } header: {
                    Text("人设 / 陪伴")
                } footer: {
                    Text("开着陪伴模式会多留意你的情绪、主动问候；关掉就只办事不寒暄。")
                }

                Section {
                    Toggle("每轮自动提炼记忆", isOn: $autoExtractMemory)
                    Toggle("定时问候", isOn: $careEnabled)
                    if careEnabled {
                        DatePicker("早上", selection: $morningTime, displayedComponents: .hourAndMinute)
                        DatePicker("晚上", selection: $eveningTime, displayedComponents: .hourAndMinute)

                        Button {
                            Task {
                                careTesting = true
                                let name = Store.shared.settings.agentName
                                let ok = await CareScheduler.fireTest(name: name)
                                careTesting = false
                                careInfo = ok ? "已排一条 5 秒后的测试通知，等它弹出来" : "通知权限没给，去系统设置里打开"
                            }
                        } label: {
                            HStack {
                                Label("发一条测试通知", systemImage: "bell.badge")
                                Spacer()
                                if careTesting { ProgressView() }
                            }
                        }

                        Button {
                            Task { await refreshCareInfo() }
                        } label: {
                            Label("检查排程状态", systemImage: "checklist")
                        }

                        if let info = careInfo {
                            Text(info)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
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
                    Picker("配色", selection: Binding(
                        get: { ThemeManager.shared.paletteID },
                        set: { ThemeManager.shared.select($0) }
                    )) {
                        ForEach(Palettes.all) { p in
                            Text(p.name).tag(p.id)
                        }
                    }
                    Picker("深浅", selection: $themeRaw) {
                        Text("深色").tag("dark")
                        Text("浅色").tag("light")
                        Text("跟随系统").tag("auto")
                    }
                    Picker("字号", selection: $fontRaw) {
                        ForEach(FontScale.allCases) { f in
                            Text(f.rawValue).tag(f.rawValue)
                        }
                    }
                    HStack {
                        Text("背景遮罩")
                        Slider(value: Binding(
                            get: { ThemeManager.shared.backgroundDim },
                            set: { ThemeManager.shared.setBackgroundDim($0) }
                        ), in: 0...1)
                        Text("\(Int(ThemeManager.shared.backgroundDim * 100))%")
                            .font(.caption.monospaced())
                            .frame(width: 42, alignment: .trailing)
                    }
                    HStack {
                        Text("面板不透明度")
                        Slider(value: Binding(
                            get: { ThemeManager.shared.glassOpacity },
                            set: { ThemeManager.shared.setGlassOpacity($0) }
                        ), in: 0.2...1)
                        Text("\(Int(ThemeManager.shared.glassOpacity * 100))%")
                            .font(.caption.monospaced())
                            .frame(width: 42, alignment: .trailing)
                    }
                } header: {
                    Text("外观")
                } footer: {
                    Text("配色一换，所有页面跟着变；深浅只影响系统控件。面板不透明度：100% = 几乎实心，20% = 透出背景。")
                }

                Section {
                    ForEach(ThemeManager.Page.allCases) { page in
                        HStack {
                            Text(page.rawValue)
                            Spacer()
                            Button(ThemeManager.shared.hasBackground(page) ? "换一张" : "选择图片") {
                                pickingPage = page
                                showBgPicker = true
                            }
                            .font(.callout)
                            if ThemeManager.shared.hasBackground(page) {
                                Button {
                                    ThemeManager.shared.clearBackground(page)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: {
                    Text("每页背景图")
                } footer: {
                    Text("给某个页面选一张图，它会用这张图做底，并自动叠一层深色遮罩保证文字看得清。不选就用当前配色的默认底。")
                }

                Section {
                    Button {
                        if let url = Backup.export() {
                            shareItems = [url]
                            showShare = true
                        }
                    } label: {
                        Label("导出备份（\(Backup.sizeText())）", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showRestore = true
                    } label: {
                        Label("从备份恢复", systemImage: "square.and.arrow.down")
                    }
                    if let m = restoreMessage {
                        Text(m).font(.caption).foregroundStyle(.secondary)
                    }
                    NavigationLink("会话存储位置") {
                        InfoView()
                    }
                } header: {
                    Text("备份与数据")
                } footer: {
                    Text("包含会话、记忆、人格、知识库索引。恢复会覆盖现有数据。")
                }
            }
            .themedScroll(.settings)
            .navigationTitle("设置")
            .fileImporter(isPresented: $showRestore, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                let n = Backup.restore(from: url)
                restoreMessage = n > 0
                    ? "已恢复 \(n) 个文件，重启 App 后生效"
                    : "恢复失败：文件格式不对"
            }
            .photosPicker(isPresented: $showBgPicker, selection: $pickedBg, matching: .images)
            .onChange(of: pickedBg) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        ThemeManager.shared.setBackground(img, for: pickingPage)
                    }
                    pickedBg = nil
                }
            }
            .sheet(isPresented: $showShare) {
                ShareSheet(items: shareItems)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save(); dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func refreshCareInfo() async {
        let status = await CareScheduler.authStatus()
        let pending = await CareScheduler.pendingSummary()
        careInfo = "权限：" + CareScheduler.statusText(status) + "\n" + pending
    }

    private func save() {
        var s = Store.shared.settings
        s.temperature = temperature
        s.maxRounds = maxRounds
        s.requireApproval = requireApproval
        s.autoSpeak = autoSpeak
        s.replyAsVoice = replyAsVoice
        s.speechRate = speechRate
        s.agentName = agentName.isEmpty ? "青露" : agentName
        s.userTitle = userTitle.isEmpty ? "主人" : userTitle
        s.tone = tone
        s.companionMode = companionMode
        s.unfilteredMode = unfilteredMode
        s.unfilteredLevel = unfilteredLevel
        s.autoExtractMemory = autoExtractMemory
        s.careEnabled = careEnabled

        let mp = Calendar.current.dateComponents([.hour, .minute], from: morningTime)
        s.careMorningHour = mp.hour ?? 8
        s.careMorningMinute = mp.minute ?? 0
        let ep = Calendar.current.dateComponents([.hour, .minute], from: eveningTime)
        s.careEveningHour = ep.hour ?? 22
        s.careEveningMinute = ep.minute ?? 30
        s.autoModelSwitch = autoModelSwitch
        s.reasoningModel = reasoningModel
        Store.shared.saveSettings(s)

        if careEnabled {
            Task {
                if await CareScheduler.requestPermission() {
                    CareScheduler.reschedule(settings: s)
                }
            }
        } else {
            CareScheduler.cancelAll()
        }

        Task { await refreshCareInfo() }
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
                ForEach(["剪贴板", "本地通知", "提醒事项", "日历", "定位", "打开链接", "HTTP 请求", "沙盒文件读写"], id: \.self) {
                    Label($0, systemImage: "checkmark.seal")
                }
            }
            Section("用量") {
                Text(UsageMeter.shared.summary)
                    .font(.caption.monospaced())
            }
        }
        .navigationTitle("关于数据")
    }
}

struct SessionsView: View {
    @EnvironmentObject private var rt: AgentRuntime
    @Environment(\.dismiss) private var dismiss

    @State private var renaming: ChatSession?
    @State private var draftTitle = ""

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
                    .swipeActions(edge: .leading) {
                        Button {
                            draftTitle = session.title
                            renaming = session
                        } label: {
                            Label("改名", systemImage: "pencil")
                        }
                        .tint(Theme.cyan)
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
            .alert("重命名会话", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("会话名称", text: $draftTitle)
                Button("保存") {
                    if let s = renaming { rt.rename(s, to: draftTitle) }
                    renaming = nil
                }
                Button("取消", role: .cancel) { renaming = nil }
            } message: {
                Text("给它起个你认得出来的名字")
            }
        }
    }
}
