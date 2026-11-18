import SwiftUI
import UIKit

struct ChatView: View {
    @EnvironmentObject private var rt: AgentRuntime
    @State private var draft = ""
    @State private var showSettings = false
    @State private var showSessions = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcript
                if let status = rt.statusLine.isEmpty ? nil : rt.statusLine {
                    statusBar(status)
                }
                if let err = rt.errorText {
                    errorBanner(err)
                }
                inputBar
            }
            .navigationTitle(rt.current.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSessions = true
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            rt.newSession()
                        } label: { Label("新对话", systemImage: "square.and.pencil") }
                        Button {
                            showSettings = true
                        } label: { Label("设置", systemImage: "gearshape") }
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
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .onChange(of: rt.current.messages.count) { _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
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
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                rt.errorText = nil
            } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12))
    }

    // MARK: - 输入区
    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("让它干点什么…", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                .focused($focused)
                .disabled(rt.isRunning)

            if rt.isRunning {
                Button {
                    rt.stop()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.red)
                }
            } else {
                Button {
                    submit()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .blue)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private func submit() {
        let text = draft
        draft = ""
        focused = false
        rt.start(text)
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
                    .background(Color.blue.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
            }

        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                if !message.content.isEmpty {
                    MarkdownText(text: message.content)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
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
                    .background(.purple.opacity(0.15), in: Capsule())
                    .foregroundStyle(.purple)
                }
                Spacer(minLength: 0)
            }

        case .tool:
            ToolRow(message: message)

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
        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
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
                    .foregroundStyle(.green)
                } else if !part.isEmpty {
                    Text(part)
                }
            }
        }
    }
}
