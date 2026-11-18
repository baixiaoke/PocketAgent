import SwiftUI

struct MemorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var memory = LongTermMemory.shared
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("手动记一条…", text: $draft)
                        Button("加") {
                            if memory.add(draft, importance: 2) { draft = "" }
                        }
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } footer: {
                    Text("它自己也会用 remember 工具往这里记。每轮对话自动带上最新的 \(24) 条。")
                }

                Section("记住了 \(memory.items.count) 条") {
                    if memory.items.isEmpty {
                        Text("还是空的。多聊聊，它会自己记。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(memory.items) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.text).font(.callout)
                            Text("\(item.when) · 重要度 \(item.importance)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { memory.remove(memory.items[i].id) }
                    }
                }
            }
            .themedScroll(.memory)
            .navigationTitle("长期记忆")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空", role: .destructive) { memory.clear() }
                }
            }
        }
    }
}
