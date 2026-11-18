import SwiftUI

/// 全局搜索：会话标题 + 每条消息内容
struct SearchSheet: View {
    @EnvironmentObject private var rt: AgentRuntime
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""

    private struct Hit: Identifiable {
        let id: String
        let session: ChatSession
        let role: String
        let snippet: String
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        ForEach(rt.sessions) { s in
                            Button {
                                rt.open(s)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(s.title).font(.callout).lineLimit(1)
                                    Text("\(s.messages.count) 条")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("全部会话")
                    }
                } else {
                    let hits = results
                    if hits.isEmpty {
                        Text("没搜到「\(query)」")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(hits) { h in
                        Button {
                            rt.open(h.session)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(h.session.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.cyan)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(h.role).font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(h.snippet)
                                    .font(.callout)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜聊天记录…")
            .themedScroll(.settings)
            .navigationTitle("搜索")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var results: [Hit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 1 else { return [] }
        var out: [Hit] = []
        for s in rt.sessions {
            for m in s.messages where m.role != .system {
                if m.content.localizedCaseInsensitiveContains(q) {
                    out.append(Hit(id: m.id,
                                   session: s,
                                   role: m.role == .user ? "我" : (m.role == .assistant ? "它" : (m.toolName ?? "工具")),
                                   snippet: m.content))
                    if out.count >= 60 { return out }
                }
            }
        }
        return out
    }
}
