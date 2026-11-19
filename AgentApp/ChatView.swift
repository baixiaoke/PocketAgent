import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PhotosUI

struct ChatView: View {
    @EnvironmentObject private var rt: AgentRuntime
    @State private var draft = ""
    @State private var showSettings = false
    @State private var showSessions = false
    @State private var showFolderPicker = false
    @State private var showCall = false
    @State private var showMemory = false
    @State private var showPersona = false
    @State private var showPhotoPicker = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var showSearch = false
    @State private var showMood = false
    @State private var renamingCurrent = false
    @State private var titleDraft = ""
    @ObservedObject private var mood = MoodStore.shared
    @StateObject private var tts = VoiceOut()
    private var voiceBusy: Bool { tts.isSpeaking }
    @State private var editing: ChatMessage?
    @StateObject private var dictation = SpeechEngine()
    @State private var dictating = false
    @ObservedObject private var folder = ExternalFolder.shared
    @ObservedObject private var themeMgr = ThemeManager.shared
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                PageBackground(page: .chat)
                VStack(spacing: 0) {
                    transcript
                    if let status = rt.statusLine.isEmpty ? nil : rt.statusLine {
                        statusBar(status)
                    }
                    if let err = rt.errorText {
                        errorBanner(err)
                    }
                    if let pending = rt.pendingApproval {
                        approvalCard(pending)
                    }
                    inputBar
                }
            }
            .navigationTitle(rt.current.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.deep.opacity(0.92), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 14) {
                        Button {
                            showSessions = true
                        } label: {
                            Image(systemName: "list.bullet.rectangle")
                        }
                        Button {
                            showCall = true
                        } label: {
                            Image(systemName: "phone.fill")
                        }
                        Button {
                            showMood = true
                        } label: {
                            Text(mood.current.emoji)
                                .font(.system(size: 18))
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            rt.newSession()
                        } label: { Label("新对话", systemImage: "square.and.pencil") }
                        Button {
                            titleDraft = rt.current.title
                            renamingCurrent = true
                        } label: { Label("重命名当前会话", systemImage: "pencil") }
                        Button {
                            showFolderPicker = true
                        } label: {
                            Label(folder.name.map { "换文件夹（现在：\($0)）" } ?? "连接文件夹…",
                                  systemImage: "folder.badge.plus")
                        }
                        if folder.name != nil {
                            Button(role: .destructive) {
                                folder.clear()
                            } label: {
                                Label("断开外部文件夹", systemImage: "folder.badge.minus")
                            }
                        }
                        Button {
                            showSettings = true
                        } label: { Label("设置", systemImage: "gearshape") }
                        Button {
                            showMemory = true
                        } label: { Label("记忆（\(LongTermMemory.shared.items.count)）", systemImage: "brain.head.profile") }
                        Button {
                            showPersona = true
                        } label: { Label("人格", systemImage: "person.text.rectangle") }
                        Button {
                            showPhotoPicker = true
                        } label: { Label("从相册读文字", systemImage: "text.viewfinder") }
                        Button {
                            showSearch = true
                        } label: { Label("搜索聊天记录", systemImage: "magnifyingglass") }
                        Button {
                            exportSession()
                        } label: { Label("导出这段对话", systemImage: "square.and.arrow.up") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showSessions) {
                SessionsView()
            }
            .fileImporter(isPresented: $showFolderPicker,
                          allowedContentTypes: [.folder],
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    folder.set(url)
                }
            }
            .fullScreenCover(isPresented: $showCall) {
                CallView().environmentObject(rt)
            }
            .sheet(isPresented: $showMemory) {
                MemorySheet()
            }
            .sheet(isPresented: $showPersona) {
                PersonaView()
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhoto, matching: .images)
            .onChange(of: pickedPhoto) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        let text = await OCRBox.recognize(img)
                        if !text.isEmpty {
                            draft += (draft.isEmpty ? "" : "\n") + text
                        }
                    }
                    pickedPhoto = nil
                }
            }
            .sheet(isPresented: $showShare) {
                ShareSheet(items: shareItems)
            }
            .sheet(isPresented: $showSearch) {
                SearchSheet().environmentObject(rt)
            }
            .sheet(isPresented: $showMood) {
                MoodSheet()
            }
            .alert("重命名会话", isPresented: $renamingCurrent) {
                TextField("会话名称", text: $titleDraft)
                Button("保存") { rt.rename(rt.current, to: titleDraft) }
                Button("取消", role: .cancel) {}
            }
            .onChange(of: rt.isRunning) { running in
                // 聊天页也支持「回答自动念出来」，通话页自己会念，别重复
                guard !running, rt.settings.autoSpeak, !showCall else { return }
                let reply = rt.lastAssistantText
                guard !reply.isEmpty else { return }
                let s = rt.settings
                Task { await tts.speakSmart(reply, settings: s, fallbackKey: Store.shared.apiKey) }
            }
            .sheet(item: $editing) { msg in
                EditMessageSheet(message: msg) { newText in
                    rt.editAndResend(msg.id, newText: newText)
                }
            }
        }
    }

    // MARK: - 对话区
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(rt.current.messages.filter { $0.role != .system }) { msg in
                        MessageRow(message: msg)
                            .id(msg.id)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = msg.content
                                } label: { Label("复制", systemImage: "doc.on.doc") }

                                if msg.role == .user {
                                    Button {
                                        editing = msg
                                    } label: { Label("编辑后重发", systemImage: "pencil") }
                                }

                                if msg.role == .assistant {
                                    Button {
                                        rt.regenerate(from: msg.id)
                                    } label: { Label("重新生成", systemImage: "arrow.clockwise") }

                                    if voiceBusy {
                                        Button {
                                            tts.stop()
                                        } label: { Label("停止朗读", systemImage: "stop.circle") }
                                    } else {
                                        Button {
                                            let s = rt.settings
                                            Task { await tts.speakSmart(msg.content, settings: s, fallbackKey: Store.shared.apiKey) }
                                        } label: { Label("念出来", systemImage: "speaker.wave.2") }
                                    }
                                }

                                if let p = msg.imagePath,
                                   let ui = UIImage(contentsOfFile: ImageGen.absolutePath(p).path) {
                                    Button {
                                        UIImageWriteToSavedPhotosAlbum(ui, nil, nil, nil)
                                    } label: { Label("存进相册", systemImage: "square.and.arrow.down") }
                                }
                            }
                    }
                    if rt.isTyping {
                        TypingIndicator()
                            .padding(.leading, 8)
                            .transition(.opacity)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .onChange(of: rt.current.messages.count) { _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onAppear {
                rt.maybeSpeakFirst()
                // 进入聊天立刻定位到最新一条
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: rt.current.id) { _ in
                // 切换会话（包括从历史列表进来）也定位到最新
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private func statusBar(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7)
            Text(text).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.yellow.opacity(0.12))
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                rt.errorText = nil
            } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.amber.opacity(0.12))
    }

    private func approvalCard(_ pending: PendingApproval) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill").font(.caption)
                Text(pending.summary).font(.caption.weight(.medium))
            }
            .foregroundStyle(Theme.amber)

            HStack(spacing: 10) {
                Button {
                    rt.resolveApproval(true)
                } label: {
                    Text("允许").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    rt.resolveApproval(false)
                } label: {
                    Text("拒绝").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .font(.footnote)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.amber.opacity(0.10))
    }

    // MARK: - 输入区
    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                toggleDictation()
            } label: {
                Image(systemName: dictating ? "mic.fill" : "mic")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(dictating ? Color.white : Theme.cyan)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(dictating ? Theme.danger : Color.white.opacity(0.06))
                    )
                    .overlay(
                        Circle().stroke(
                            dictating ? Theme.danger.opacity(0.8) : Theme.cyan.opacity(0.35),
                            lineWidth: 0.8)
                    )
                    .neonGlow(dictating ? Theme.danger : Theme.cyan, radius: 8, opacity: 0.5)
                    .scaleEffect(dictating ? 1.04 : 1.0)
                    .animation(.easeInOut(duration: 0.18), value: dictating)
            }
            .disabled(rt.isRunning)

            TextField(dictating ? "在听…" : "让它干点什么…", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassFill(radius: 20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(focused ? Theme.cyan.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 0.8)
                )
                .focused($focused)
                .onChange(of: draft) { v in rt.userTyping = !v.isEmpty }
                .disabled(rt.isRunning)

            if rt.isRunning {
                Button {
                    rt.stop()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.danger)
                        .neonGlow(Theme.danger, radius: 8, opacity: 0.6)
                }
            } else {
                Button {
                    submit()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : Theme.cyan)
                        .neonGlow(Theme.cyan, radius: 8, opacity: 0.7)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Theme.panel.opacity(0.10 + 0.80 * themeMgr.glassOpacity))
            }
        }
        .overlay(alignment: .top) { PulseBar().opacity(0.7) }
    }

    private func submit() {
        let text = draft
        draft = ""
        focused = false
        if dictating {
            dictation.stop()
            dictating = false
        }
        rt.markUserActivity()
        rt.start(text)
    }

    /// 输入框语音转写：边说边出字，说完不自动发送
    private func toggleDictation() {
        if dictating {
            dictation.stop()
            dictating = false
            return
        }
        Task {
            let ok = await dictation.requestAuthorization()
            guard ok else { return }

            let prefix = draft
            dictation.bypassReview = true          // 听写不做拒答式过滤
            dictation.silenceTimeout = 2.2
            dictation.onPartial = { t in
                draft = prefix.isEmpty ? t : prefix + t
            }
            dictation.onFinal = { t in
                draft = prefix.isEmpty ? t : prefix + t
                dictating = false
            }
            dictation.start()
            dictating = true
        }
    }

    private func exportSession() {
        let md = Exporter.markdown(for: rt.current, agentName: rt.settings.agentName)
        guard let url = Exporter.writeTempFile(md, name: rt.current.title) else { return }
        shareItems = [url]
        showShare = true
    }
}

// MARK: - 单条消息
struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.userBubble, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
                    )
                    .foregroundStyle(.white)
                    .neonGlow(Theme.violet, radius: 10, opacity: 0.35)
                    .textSelection(.enabled)
            }

        case .assistant:
            VStack(alignment: .leading, spacing: 10) {
                // 「||| 分隔」按人格设定拆成多个气泡，像连发消息
                if rt.settings.replyAsVoice {
                    VoiceBar(text: message.content)
                        .padding(.leading, 6)
                }
                ForEach(Array(BubbleSplitter.split(message.content).enumerated()), id: \.offset) { idx, part in
                    MarkdownText(text: part)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .glassCard(radius: idx == 0 ? 16 : 18, tint: Theme.cyan)
                        .padding(.leading, idx == 0 ? 0 : 8)   // 连发的第二条往右错一点，像一条条发的
                        .textSelection(.enabled)
                }
                if let calls = message.toolCalls, !calls.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "hammer.fill").font(.caption2)
                        Text(calls.map { $0.function.name }.joined(separator: " · "))
                            .font(.caption2.monospaced())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.violet.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.violet)
                }
                Text(Self.timeText(message.createdAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.28))
                    .padding(.leading, 6)
                Spacer(minLength: 0)
            }

        case .tool:
            VStack(alignment: .leading, spacing: 8) {
                if let p = message.imagePath,
                   let ui = UIImage(contentsOfFile: ImageGen.absolutePath(p).path) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 262)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Theme.cyan.opacity(0.35), lineWidth: 0.8)
                        )
                        .neonGlow(Theme.cyan, radius: 12, opacity: 0.3)
                }
                ToolRow(message: message)
            }

        case .system:
            EmptyView()
        }
    }
}

struct ToolRow: View {
    let message: ChatMessage

    var body: some View {
        DisclosureGroup {
            Text(message.content)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver.fill").font(.caption2)
                Text("\(message.toolName ?? "tool") 返回")
                    .font(.caption2.monospaced())
                Text(String(message.content.prefix(40)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassCard(radius: 12, tint: Theme.violet)
        .accentColor(.gray)
    }
}

// MARK: - 轻量 Markdown（只处理代码块与等宽，够读就行）
struct MarkdownText: View {
    let text: String

    var body: some View {
        let parts = text.components(separatedBy: "```")
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parts.enumerated()), id: \.offset) { idx, part in
                if idx % 2 == 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(part.trimmingCharacters(in: .newlines))
                            .font(.caption.monospaced())
                            .padding(10)
                            .textSelection(.enabled)
                    }
                    .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(Theme.mint)
                } else if !part.isEmpty {
                    Text(part)
                }
            }
        }
    }
}

// MARK: - 系统分享面板
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - 编辑消息
struct EditMessageSheet: View {
    @Environment(\.dismiss) private var dismiss
    let message: ChatMessage
    let onSave: (String) -> Void

    @State private var draft: String

    init(message: ChatMessage, onSave: @escaping (String) -> Void) {
        self.message = message
        self.onSave = onSave
        _draft = State(initialValue: message.content)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $draft)
                        .font(.callout)
                        .frame(minHeight: 160)
                } footer: {
                    Text("保存后会把这条之后的内容删掉，用新内容重新问一遍。")
                }
            }
            .navigationTitle("编辑消息")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("重发") {
                        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { dismiss(); return }
                        onSave(t)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

extension MessageRow {
    /// 拆气泡：优先按 ||| ；模型没写就按句号/问号/感叹号自动拆（仅限短对话，不动长文与代码）
    static func splitBubbles(_ text: String) -> [String] {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }

        if raw.contains("|||") {
            return raw.components(separatedBy: "|||")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        // 长文、代码、列表不拆，避免把正经内容打散
        let looksLong = raw.count > 160
        let looksCode = raw.contains("```") || raw.contains("\n- ") || raw.contains("\n1.")
        let multiLine = raw.filter { $0 == "\n" }.count >= 2
        if looksLong || looksCode || multiLine {
            return [raw]
        }

        // 按句末标点切开，保留标点
        var parts: [String] = []
        var current = ""
        let enders: Set<Character> = ["。", "！", "？", "…", "!", "?"]
        for ch in raw {
            current.append(ch)
            if enders.contains(ch) {
                let t = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { parts.append(t) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { parts.append(tail) }

        // 太碎就并回来（少于 2 段说明拆不动）
        if parts.count < 2 { return [raw] }
        // 超过 5 段的，把后面的并成一段，避免刷屏
        if parts.count > 5 {
            let head = Array(parts.prefix(4))
            let rest = parts.dropFirst(4).joined()
            return head + [rest]
        }
        return parts
    }
}

extension MessageRow {
    /// 时间戳：今天只显示时分，昨天显示「昨天」，更早显示日期
    static func timeText(_ date: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(date) {
            f.dateFormat = "HH:mm"
            return f.string(from: date)
        }
        if cal.isDateInYesterday(date) { return "昨天" }
        f.dateFormat = "M月d日"
        return f.string(from: date)
    }
}

/// 「对方正在输入」的三个点
struct TypingIndicator: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Theme.cyan.opacity(phase == i ? 0.95 : 0.35))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassCard(radius: 16, tint: Theme.cyan)
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}
/// 微信式语音条：点一下才合成播放，长度按字数估算
struct VoiceBar: View {
    let text: String

    @StateObject private var tts = VoiceOut()
    @State private var playing = false

    private var seconds: Int {
        max(1, min(60, Int(Double(text.count) * 0.18)))
    }
    private var width: CGFloat {
        90 + min(120, CGFloat(seconds) * 4)
    }

    var body: some View {
        Button {
            if playing {
                tts.stop()
                playing = false
                return
            }
            playing = true
            let s = Store.shared.settings
            Task {
                await tts.speakSmart(text, settings: s, fallbackKey: Store.shared.apiKey)
                await MainActor.run { playing = false }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: playing ? "waveform" : "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(seconds)\"")
                    .font(.caption2.monospaced())
            }
            .foregroundStyle(Theme.cyan)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: width, alignment: .leading)
            .background(Theme.cyan.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(Theme.cyan.opacity(0.30), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }
}