import SwiftUI

struct BatchCategoryOption {
    let name: String
    let subcategories: [String]
}

struct BatchRuleOption: Identifiable {
    let id: UUID
    let title: String
    var subtitle: String = ""
    var category: String = ""
    var subcategory: String = ""
}

struct BatchClassification: Equatable {
    let category: String
    let subcategory: String
}

struct BatchEdit: Equatable {
    let ruleIDs: Set<UUID>
    let classification: BatchClassification?
    let durationYears: Int?
}

struct BatchRemovalPreview: Equatable {
    let ruleCount: Int
    let eventCount: Int
}

struct BatchActionsView: View {
    let rules: [BatchRuleOption]
    let categories: [BatchCategoryOption]
    let preview: (BatchEdit) throws -> BatchDurationPreview
    let apply: (BatchEdit) throws -> Void
    let removalPreview: (Set<UUID>) throws -> BatchRemovalPreview
    let remove: (Set<UUID>) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var selection: Set<UUID>
    @State private var changeClassification = false
    @State private var changeDuration = false
    @State private var category = ""
    @State private var subcategory = ""
    @State private var years = 1
    @State private var review: BatchDurationPreview?
    @State private var removal: BatchRemovalPreview?
    @State private var removalSelection: Set<UUID> = []
    @State private var confirmation: Confirmation?
    private enum Confirmation { case apply, removal }
    @State private var failure: String?

    init(rules: [BatchRuleOption], initiallySelected: Set<UUID>, categories: [BatchCategoryOption],
         preview: @escaping (BatchEdit) throws -> BatchDurationPreview, apply: @escaping (BatchEdit) throws -> Void,
         removalPreview: @escaping (Set<UUID>) throws -> BatchRemovalPreview, remove: @escaping (Set<UUID>) throws -> Void) {
        self.rules = rules
        self.categories = categories
        self.preview = preview
        self.apply = apply
        self.removalPreview = removalPreview
        self.remove = remove
        _selection = State(initialValue: initiallySelected.intersection(rules.map(\.id)))
    }

    private var categoryName: String { category.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var subcategoryName: String { subcategory.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var availableSubcategories: [String] {
        categories.first { $0.name == categoryName }?.subcategories ?? []
    }

    private var edit: BatchEdit? {
        guard !selection.isEmpty, changeClassification || changeDuration,
              !changeClassification || !categoryName.isEmpty else { return nil }
        return BatchEdit(ruleIDs: selection,
                         classification: changeClassification
                            ? BatchClassification(category: categoryName, subcategory: subcategoryName) : nil,
                         durationYears: changeDuration ? years : nil)
    }

    private var categoryNames: [String] {
        uniqueNames(rules.map(\.category))
    }

    private func uniqueNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    private var showingConfirmation: Binding<Bool> {
        .init(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("更改分類／次類", isOn: $changeClassification)
                        .accessibilityIdentifier("batch-edit-classification")
                    if changeClassification {
                        let layout = textSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                        layout {
                            entry("分類", placeholder: "必填", text: $category, options: categories.map(\.name))
                            entry("次類", placeholder: "可留空", text: $subcategory,
                                  options: availableSubcategories, canClear: true)
                        }
                    }
                } footer: {
                    if changeClassification {
                        Text("次類留空會把規則直接放在分類下。只改分類不會寫入行事曆。")
                    }
                }
                Section {
                    Toggle("更改重複期間", isOn: $changeDuration)
                        .accessibilityIdentifier("batch-edit-duration")
                    if changeDuration {
                        Stepper("重複期間：\(years) 年", value: $years, in: 1...100)
                            .accessibilityIdentifier("batch-duration-years")
                    }
                } footer: {
                    if changeDuration {
                        Text("每條規則都從原本的起始日換算新的截止日。")
                    }
                }
                Section {
                    if rules.isEmpty {
                        Text("沒有可選的規則").foregroundStyle(.secondary)
                    } else {
                        Button(selection.count == rules.count ? "取消全選" : "全選") {
                            selection = selection.count == rules.count ? [] : Set(rules.map(\.id))
                        }
                        ForEach(categoryNames, id: \.self) { category in
                            let grouped = rules.filter { $0.category == category }
                            if !category.isEmpty {
                                groupSelection(category, rules: grouped, isSubcategory: false)
                            }
                            ForEach(uniqueNames(grouped.map(\.subcategory)), id: \.self) { subcategory in
                                let children = grouped.filter { $0.subcategory == subcategory }
                                if !subcategory.isEmpty {
                                    groupSelection(subcategory, rules: children, isSubcategory: true)
                                }
                                ForEach(children, content: ruleSelection)
                            }
                        }
                    }
                } header: {
                    Text("選擇規則（\(selection.count) 條）")
                }
                if let review, changeDuration {
                    BatchDurationReviewSections(review: review)
                }
                if changeDuration {
                    Section {
                        Button("預覽變更", action: prepare)
                            .disabled(edit == nil)
                    }
                }
                Section {
                    Button(role: .destructive, action: prepareRemoval) {
                        Label("整批移除", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .disabled(selection.isEmpty)
                } footer: {
                    Text("移除是獨立操作，不會套用上面的調整；會移除已選規則、關聯子規則，以及它們建立且尚未開始的事件。")
                }
            }
            .navigationTitle("批次調整")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("套用") { confirmation = .apply }
                        .fontWeight(.semibold)
                        .disabled(edit == nil || (changeDuration && review == nil))
                        .accessibilityIdentifier("batch-apply")
                }
            }
            .onChange(of: edit) { _, _ in review = nil }
            .confirmationDialog(confirmation == .removal ? "確定整批移除？" : "套用至 \(selection.count) 條規則？",
                                isPresented: showingConfirmation, titleVisibility: .visible) {
                if confirmation == .removal, let proposed = removal {
                    Button("移除 \(proposed.ruleCount) 條規則", role: .destructive) { confirmRemoval(proposed) }
                } else {
                    Button("確認套用", action: commit)
                }
                Button("取消", role: .cancel) {}
            } message: {
                if confirmation == .removal, let proposed = removal {
                    Text("將移除 \(proposed.ruleCount) 條規則（含子規則）和 \(proposed.eventCount) 筆尚未開始的事件。已開始的事件會保留。")
                } else {
                    Text(applySummary)
                }
            }
            .alert("無法完成操作", isPresented: Binding(
                get: { failure != nil }, set: { if !$0 { failure = nil } }
            )) {
                Button("好", role: .cancel) { failure = nil }
            } message: { Text(failure ?? "") }
        }
    }

    private func groupSelection(_ label: String, rules: [BatchRuleOption], isSubcategory: Bool) -> some View {
        let ids = Set(rules.map(\.id))
        let selectedCount = ids.intersection(selection).count
        return Button {
            if selectedCount == ids.count {
                selection.subtract(ids)
            } else {
                selection.formUnion(ids)
            }
        } label: {
            HStack {
                Image(systemName: isSubcategory ? "folder" : "folder.fill")
                Text(label).fontWeight(isSubcategory ? .regular : .semibold)
                Spacer()
                Text("\(selectedCount)／\(ids.count)").foregroundStyle(.secondary)
                Image(systemName: selectedCount == ids.count ? "checkmark.square.fill" : "square")
            }
            .padding(.leading, isSubcategory ? 16 : 0)
        }
        .accessibilityLabel("選擇\(isSubcategory ? "次類" : "分類")「\(label)」")
        .accessibilityValue("已選 \(selectedCount) 筆，共 \(ids.count) 筆")
    }

    private func ruleSelection(_ rule: BatchRuleOption) -> some View {
        Toggle(isOn: binding(for: rule.id)) {
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.title)
                if !rule.subtitle.isEmpty {
                    Text(rule.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, rule.subcategory.isEmpty ? 8 : 24)
        .accessibilityIdentifier("batch-rule-option-\(rule.id.uuidString)")
    }

    private var applySummary: String {
        guard let edit else { return "" }
        var lines: [String] = []
        if let classification = edit.classification {
            let path = classification.subcategory.isEmpty
                ? classification.category : "\(classification.category)／\(classification.subcategory)"
            lines.append("分類改為「\(path)」。")
        }
        if let duration = edit.durationYears {
            lines.append("重複期間改為 \(duration) 年，不改動已開始的事件。")
        }
        return lines.joined(separator: "\n")
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        .init(get: { selection.contains(id) }, set: {
            if $0 { selection.insert(id) } else { selection.remove(id) }
        })
    }

    private func prepare() {
        guard let edit else { return }
        do {
            review = try preview(edit)
        } catch {
            review = nil
            failure = error.localizedDescription
        }
    }

    private func commit() {
        guard let edit else { return }
        do {
            if edit.durationYears != nil {
                guard let confirmed = review else { return }
                let current = try preview(edit)
                guard confirmed.matches(current) else {
                    review = current
                    failure = "行事曆內容已變更，請重新確認下面的預覽。"
                    return
                }
            }
            try apply(edit)
            dismiss()
        } catch {
            review = nil
            failure = error.localizedDescription
        }
    }

    private func prepareRemoval() {
        let selected = selection
        do {
            removal = try removalPreview(selected)
            removalSelection = selected
            confirmation = .removal
        } catch {
            failure = error.localizedDescription
        }
    }

    private func confirmRemoval(_ proposed: BatchRemovalPreview) {
        do {
            guard removalSelection == selection,
                  try removalPreview(removalSelection) == proposed else {
                failure = "受影響的資料已變更，請重新選擇「整批移除」再確認。"
                return
            }
            try remove(removalSelection)
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }

    private func entry(_ label: String, placeholder: String, text: Binding<String>, options: [String], canClear: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                TextField(placeholder, text: text)
                    .accessibilityLabel(label)
                Menu {
                    if canClear {
                        Button("不分次類") { text.wrappedValue = "" }
                    }
                    ForEach(options, id: \.self) { option in
                        Button(option) { text.wrappedValue = option }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .frame(width: 36, height: 44)
                }
                .disabled(options.isEmpty && !canClear)
                .accessibilityLabel("選擇既有\(label)")
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
