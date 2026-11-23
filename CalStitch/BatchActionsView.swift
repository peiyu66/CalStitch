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
    @State private var years = 5
    @State private var removalMode = false
    @State private var previewExpanded = false
    @State private var cachedReview: CachedReview?
    @State private var confirmation: Confirmation?
    @State private var failure: String?

    private enum Confirmation {
        case apply(BatchEdit)
        case removal(BatchRemovalPreview, Set<UUID>)
    }

    private struct CachedReview {
        let edit: BatchEdit
        let result: Result<BatchDurationPreview, Error>
    }

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
        guard !removalMode, !selection.isEmpty, changeClassification || changeDuration,
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

    private var currentReview: CachedReview? {
        guard let edit, cachedReview?.edit == edit else { return nil }
        return cachedReview
    }

    private var canApply: Bool {
        if removalMode { return !selection.isEmpty }
        guard let edit else { return false }
        if edit.durationYears == nil { return true }
        guard case .success? = currentReview?.result else { return false }
        return true
    }

    private var removalModeBinding: Binding<Bool> {
        .init(get: { removalMode }, set: { enabled in
            removalMode = enabled
            if enabled {
                changeClassification = false
                changeDuration = false
                previewExpanded = false
                cachedReview = nil
            }
        })
    }

    private var confirmationTitle: String {
        if case .removal = confirmation { return "確定整批移除？" }
        return "套用至 \(selection.count) 條規則？"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("更改分類／次類", isOn: $changeClassification)
                        .disabled(removalMode)
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
                        .disabled(removalMode)
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
                    Toggle("整批移除", isOn: removalModeBinding)
                        .accessibilityIdentifier("batch-edit-removal")
                } footer: {
                    if removalMode {
                        Text("按套用後會先確認，不會立即刪除。")
                    }
                }
                Section {
                    if rules.isEmpty {
                        Text("沒有可選的規則").foregroundStyle(.secondary)
                    } else {
                        selectionControl("全選", ids: Set(rules.map(\.id)))
                            .accessibilityIdentifier("batch-select-all")
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
                if changeDuration {
                    Section {
                        DisclosureGroup("預覽變更", isExpanded: $previewExpanded) {
                            previewContent
                        }
                        .accessibilityIdentifier("batch-preview-disclosure")
                    }
                }
                if let failure {
                    Section {
                        Label(failure, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("批次調整")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("套用", action: beginConfirmation)
                        .fontWeight(.semibold)
                        .disabled(!canApply)
                        .accessibilityIdentifier("batch-apply")
                }
            }
            .onChange(of: edit) { _, _ in
                cachedReview = nil
                failure = nil
                if previewExpanded { preparePreview() }
            }
            .onChange(of: previewExpanded) { _, expanded in
                if expanded { preparePreview() }
            }
            .alert(confirmationTitle, isPresented: showingConfirmation, presenting: confirmation) { presented in
                switch presented {
                case let .apply(request):
                    Button("確認套用") { commit(request) }
                case let .removal(review, selected):
                    Button("移除", role: .destructive) { confirmRemoval(review, selected: selected) }
                }
                Button("取消", role: .cancel) {}
            } message: { presented in
                switch presented {
                case let .apply(request):
                    Text(applySummary(request))
                case let .removal(review, _):
                    Text("將移除 \(review.ruleCount) 條規則（含子規則）和 \(review.eventCount) 筆尚未開始的事件。已開始的事件會保留。")
                }
            }
        }
    }

    private func groupSelection(_ label: String, rules: [BatchRuleOption], isSubcategory: Bool) -> some View {
        selectionControl(label, ids: Set(rules.map(\.id)), isSubcategory: isSubcategory,
                         icon: isSubcategory ? "folder" : "folder.fill")
            .accessibilityLabel("選擇\(isSubcategory ? "次類" : "分類")「\(label)」")
    }

    private func selectionControl(_ label: String, ids: Set<UUID>, isSubcategory: Bool = false,
                                  icon: String? = nil) -> some View {
        let selectedCount = ids.intersection(selection).count
        let checked = selectedCount == ids.count
        return Button {
            if checked { selection.subtract(ids) }
            else { selection.formUnion(ids) }
        } label: {
            HStack {
                if let icon { Image(systemName: icon) }
                Text(label).fontWeight(isSubcategory ? .regular : .semibold)
                Spacer()
                Text("\(selectedCount)／\(ids.count)").foregroundStyle(.secondary)
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .accessibilityHidden(true)
            }
            .padding(.leading, isSubcategory ? 16 : 0)
        }
        .accessibilityAddTraits(checked ? [.isSelected] : [])
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

    private func applySummary(_ edit: BatchEdit) -> String {
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

    @ViewBuilder
    private var previewContent: some View {
        if let review = currentReview {
            switch review.result {
            case let .success(prepared):
                BatchDurationReviewSections(review: prepared)
            case let .failure(error):
                Label(error.localizedDescription, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                Button("重試") { preparePreview(force: true) }
            }
        } else if edit == nil {
            Text("請先選擇規則並填妥必要欄位。").foregroundStyle(.secondary)
        } else {
            Button("重試") { preparePreview(force: true) }
        }
    }

    private func preparePreview(force: Bool = false) {
        guard let edit, edit.durationYears != nil, force || currentReview == nil else { return }
        cachedReview = CachedReview(edit: edit, result: Result { try preview(edit) })
    }

    private func beginConfirmation() {
        guard canApply else { return }
        failure = nil
        if removalMode {
            let selected = selection
            do {
                confirmation = .removal(try removalPreview(selected), selected)
            } catch {
                failure = error.localizedDescription
            }
        } else if let edit {
            confirmation = .apply(edit)
        }
    }

    private func commit(_ request: BatchEdit) {
        guard let edit, edit == request else {
            failure = "調整條件已變更，請重新確認。"
            return
        }
        do {
            if edit.durationYears != nil {
                guard case let .success(confirmed)? = currentReview?.result else { return }
                let current = try preview(edit)
                guard confirmed.matches(current) else {
                    cachedReview = CachedReview(edit: edit, result: .success(current))
                    previewExpanded = true
                    failure = "行事曆內容已變更，請重新確認下面的預覽。"
                    return
                }
            }
            try apply(edit)
            dismiss()
        } catch {
            cachedReview = nil
            failure = error.localizedDescription
        }
    }

    private func confirmRemoval(_ proposed: BatchRemovalPreview, selected: Set<UUID>) {
        do {
            guard removalMode, selected == selection,
                  try removalPreview(selected) == proposed else {
                failure = "受影響的資料已變更，請重新按「套用」再確認。"
                return
            }
            try remove(selected)
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
