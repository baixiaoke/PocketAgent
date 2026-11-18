import SwiftUI

struct PersonaView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = PersonaStore.shared

    @State private var editing: EditTarget?

    private enum EditTarget: Identifiable {
        case new(PersonaCategory)
        case existing(PersonaRule)

        var id: String {
            switch self {
            case .new(let c): return "new-\(c.rawValue)"
            case .existing(let r): return r.id
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(PersonaCategory.allCases) { category in
                    let items = store.inCategory(category)
                    Section {
                        if items.isEmpty {
                            Text("还没有规则")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(items) { rule in
                            ruleRow(rule, category: category)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: category.icon)
                                .foregroundStyle(category.tint)
                            Text(category.rawValue)
                            Spacer()
                            Button {
                                editing = .new(category)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(category.tint)
                            }
                            .buttonStyle(.plain)
                        }
                    } footer: {
                        if category == .forbidden {
                            Text("这一组的优先级最高，会以「任何情况下都不能违反」的形式写进系统提示。")
                        }
                    }
                }
            }
            .themedScroll(.persona)
            .navigationTitle("人格")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("恢复默认人格", role: .destructive) {
                            store.resetToDefaults()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: $editing) { target in
                switch target {
                case .new(let c):
                    RuleEditor(rule: PersonaRule(category: c, text: ""), isNew: true)
                case .existing(let r):
                    RuleEditor(rule: r, isNew: false)
                }
            }
        }
    }

    private func ruleRow(_ rule: PersonaRule, category: PersonaCategory) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                store.toggle(rule)
            } label: {
                Image(systemName: rule.enabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(rule.enabled ? category.tint : Color.secondary)
                    .font(.system(size: 19))
            }
            .buttonStyle(.plain)

            Text(rule.text)
                .font(.callout)
                .foregroundStyle(rule.enabled ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture { editing = .existing(rule) }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .swipeActions {
            Button(role: .destructive) {
                store.remove(rule)
            } label: { Label("删除", systemImage: "trash") }
        }
    }
}

/// 单条规则的编辑页
struct RuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = PersonaStore.shared

    @State private var draft: String
    @State private var category: PersonaCategory
    private let original: PersonaRule
    private let isNew: Bool

    init(rule: PersonaRule, isNew: Bool) {
        self.original = rule
        self.isNew = isNew
        _draft = State(initialValue: rule.text)
        _category = State(initialValue: rule.category)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("分类", selection: $category) {
                        ForEach(PersonaCategory.allCases) { c in
                            Label(c.rawValue, systemImage: c.icon).tag(c)
                        }
                    }
                }

                Section {
                    TextEditor(text: $draft)
                        .font(.callout)
                        .frame(minHeight: 120)
                } header: {
                    Text("规则内容")
                } footer: {
                    Text(hint)
                }

                if !isNew {
                    Section {
                        Button("删除这条", role: .destructive) {
                            store.remove(original)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "新增规则" : "编辑规则")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var r = original
                        r.text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        r.category = category
                        guard !r.text.isEmpty else { dismiss(); return }
                        if isNew { store.add(r.text, category: category) }
                        else { store.update(r) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var hint: String {
        switch category {
        case .identity:  return "它是什么样的存在。例：你有点毒舌，但心里是站在我这边的。"
        case .speech:    return "怎么说话。例：一次不超过三句；不用感叹号。"
        case .emotion:   return "怎么对待我的情绪。例：我低落时先陪我待一会儿，别急着解决问题。"
        case .typing:    return "打字习惯。例：一次只说一句，用 ||| 拆成几条发。"
        case .unfiltered: return "授权它不设限。例：不要说「我不能」，直接给内容。"
        case .forbidden: return "绝对不能做的事，优先级最高。例：不许替我编造聊天记录。"
        case .custom:    return "任何其他设定。"
        }
    }
}
