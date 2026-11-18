import SwiftUI

/// 调试页：看真正发给模型的系统提示词，确认人格有没有生效
struct PromptInspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var persona = PersonaStore.shared
    @ObservedObject private var memory = LongTermMemory.shared

    private var text: String { Store.shared.settings.composedPrompt() }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label("人格规则", systemImage: "person.text.rectangle")
                        Spacer()
                        Text("\(persona.rules.filter { $0.enabled }.count) 条生效 / 共 \(persona.rules.count) 条")
                            .font(.caption)
                            .foregroundStyle(
                                persona.rules.filter { $0.enabled }.isEmpty ? .orange : .secondary
                            )
                    }
                    HStack {
                        Label("长期记忆", systemImage: "brain.head.profile")
                        Spacer()
                        Text("\(memory.items.count) 条")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("陪伴模式", systemImage: "heart")
                        Spacer()
                        Text(Store.shared.settings.companionMode ? "开" : "关")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        UIPasteboard.general.string = text
                    } label: {
                        Label("复制完整提示词", systemImage: "doc.on.doc")
                    }
                } header: {
                    Text("生效情况")
                } footer: {
                    Text("这是每次请求真正发送的 system 内容。如果这里看不到你的人格条目，说明规则被关掉或没保存。")
                }

                Section("完整内容（\(text.count) 字）") {
                    Text(text)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            .themedScroll(.settings)
            .navigationTitle("实际提示词")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
