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

struct BatchRepeatDuration: Equatable {
    let count: Int
    let unit: PeriodUnit

    var caption: String { "\(count) \(unit.displayLabel(count: count))" }
}

struct BatchEdit: Equatable {
    let ruleIDs: Set<UUID>
    let classification: BatchClassification?
    let duration: BatchRepeatDuration?
}

struct BatchRemovalRule: Identifiable, Equatable {
    let id: UUID
    let title: String
    let depth: Int
}

typealias BatchRemovalEvent = CalendarRemovalEvent

struct BatchRemovalPreview: Equatable {
    let rules: [BatchRemovalRule]
    let events: [BatchRemovalEvent]
    var retained: [CalendarPreviewEvent] = []
    var ruleCount: Int { rules.count }
    var eventCount: Int { events.count }
}

struct BatchActionsView: View {
    let rules: [BatchRuleOption]
    let categories: [BatchCategoryOption]
    let preview: (BatchEdit) throws -> BatchDurationPreview
    let apply: (BatchEdit) throws -> Void
    let removalPreview: (Set<UUID>) throws -> BatchRemovalPreview
    let remove: (Set<UUID>, BatchRemovalPreview) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var selection: Set<UUID>
    @State private var changeClassification = false
    @State private var changeDuration = false
    @State private var category = ""
    @State private var subcategory = ""
    @State private var classificationWasEdited = false
    @State private var durationCount = 5
    @State private var durationUnit: PeriodUnit = .year

    @State private var removalMode = false
    @State private var previewExpanded = false
    @State private var cachedReview: CachedReview?
    @State private var cachedRemoval: CachedRemoval?
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
    private struct CachedRemoval {
        let selection: Set<UUID>
        let result: Result<BatchRemovalPreview, Error>
    }

    init(rules: [BatchRuleOption], initiallySelected: Set<UUID>, categories: [BatchCategoryOption],
         preview: @escaping (BatchEdit) throws -> BatchDurationPreview, apply: @escaping (BatchEdit) throws -> Void,
         removalPreview: @escaping (Set<UUID>) throws -> BatchRemovalPreview,
         remove: @escaping (Set<UUID>, BatchRemovalPreview) throws -> Void) {
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
                         duration: changeDuration ? BatchRepeatDuration(count: durationCount, unit: durationUnit) : nil)
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

    private var currentRemoval: CachedRemoval? {
        guard removalMode, !selection.isEmpty, cachedRemoval?.selection == selection else { return nil }
        return cachedRemoval
    }

    private var canApply: Bool {
        if removalMode {
            guard case .success? = currentRemoval?.result else { return false }
            return true
        }
        guard case let .success(review)? = currentReview?.result else { return false }
        return review.hasChanges
    }

    private var firstSelectedRuleInList: BatchRuleOption? {
        for category in categoryNames {
            let grouped = rules.filter { $0.category == category }
            for subcategory in uniqueNames(grouped.map(\.subcategory)) {
                if let first = grouped.first(where: { $0.subcategory == subcategory && selection.contains($0.id) }) {
                    return first
                }
            }
        }
        return nil
    }

    private var classificationModeBinding: Binding<Bool> {
        Binding(get: { changeClassification }, set: { enabled in
            if enabled && !classificationWasEdited {
                let first = firstSelectedRuleInList
                category = first?.category ?? ""
                subcategory = first?.subcategory ?? ""
            }
            changeClassification = enabled
        })
    }

    private func classificationField(_ value: Binding<String>) -> Binding<String> {
        Binding(get: { value.wrappedValue }, set: { newValue in
            classificationWasEdited = true
            value.wrappedValue = newValue
        })
    }

    private var removalModeBinding: Binding<Bool> {
        .init(get: { removalMode }, set: { enabled in
            removalMode = enabled
            cachedRemoval = nil
            failure = nil
            if enabled {
                changeClassification = false
                changeDuration = false
                previewExpanded = true
                cachedReview = nil
                preparePreview()
            } else {
                previewExpanded = false
            }
        })
    }

    private var confirmationTitle: String {
        if case .removal = confirmation { return L10n.text("確定整批移除？", "Remove the selected rules?") }
        return L10n.text("套用至 \(selection.count) 條規則？", "Apply to \(selection.count) selected?")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(L10n.text("更改分類／次類", "Change Category or Subcategory"), isOn: classificationModeBinding)
                        .disabled(removalMode)
                        .accessibilityIdentifier("batch-edit-classification")
                    if changeClassification {
                        let layout = textSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                        layout {
                            CategoryEntryField(selection: classificationField($category), options: categories.map(\.name), isSubcategory: false,
                                               fieldID: "batch-category", menuID: "batch-category-options")
                            CategoryEntryField(selection: classificationField($subcategory), options: availableSubcategories, isSubcategory: true,
                                               fieldID: "batch-subcategory", menuID: "batch-subcategory-options")
                        }
                    }
                } footer: {
                    if changeClassification {
                        Text(L10n.text("次類留空會把規則直接放在分類下。只改分類不會寫入行事曆。", "Leave the subcategory blank to keep rules directly in the category. Changing categories does not update Calendar."))
                    }
                }
                Section {
                    Toggle(L10n.text("更改重複期間", "Change Repeat Duration"), isOn: $changeDuration)
                        .disabled(removalMode)
                        .accessibilityIdentifier("batch-edit-duration")
                    if changeDuration {
                        LabeledContent(L10n.text("重複期間單位", "Repeat Duration Unit")) {
                            Menu {
                                ForEach([PeriodUnit.year, .month, .day]) { unit in
                                    Button { durationUnit = unit } label: {
                                        if durationUnit == unit {
                                            Label(unit.displayLabel(), systemImage: "checkmark")
                                        } else {
                                            Text(unit.displayLabel())
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(durationUnit.displayLabel())
                                    Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .accessibilityLabel(L10n.text("重複期間單位：\(durationUnit.displayLabel())",
                                                         "Repeat Duration Unit: \(durationUnit.displayLabel())"))
                            .accessibilityIdentifier("batch-duration-unit")
                        }
                        let duration = BatchRepeatDuration(count: durationCount, unit: durationUnit)
                        Stepper(L10n.text("重複期間：\(duration.caption)", "Repeat duration: \(duration.caption)"),
                                value: $durationCount, in: 1...999)
                            .accessibilityIdentifier("batch-duration-years")
                    }
                } footer: {
                    if changeDuration {
                        Text(L10n.text("每條規則都從原本的起始日換算新的截止日。", "The new end date is calculated from each rule’s original start date."))
                    }
                }
                Section {
                    Toggle(L10n.text("整批移除", "Remove Selected Rules"), isOn: removalModeBinding)
                        .accessibilityIdentifier("batch-edit-removal")
                } footer: {
                    if removalMode {
                        Text(L10n.text("按套用後會先確認，不會立即刪除。", "Apply opens a confirmation before anything is removed."))
                    } else if !changeClassification && !changeDuration {
                        Text(L10n.text("請先選擇要調整的項目。", "Choose what to change first."))
                    }
                }
                Section {
                    if rules.isEmpty {
                        Text(L10n.text("沒有可選的規則", "No rules to select")).foregroundStyle(.secondary)
                    } else {
                        selectionControl(L10n.text("全選", "Select All"), ids: Set(rules.map(\.id)))
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
                    Text(L10n.text("選擇規則（\(selection.count) 條）", "Select Rules (\(selection.count))"))
                }
                if changeClassification || changeDuration || removalMode {
                    Section {
                        DisclosureGroup(L10n.text("預覽變更", "Preview Changes"), isExpanded: $previewExpanded) {
                            previewContent
                        }
                        .accessibilityIdentifier("batch-preview-disclosure")
                    } footer: {
                        if case let .success(review)? = currentReview?.result, !review.hasChanges {
                            Text(L10n.text("沒有需要套用的變更。", "No changes to apply."))
                        }
                    }
                }
                if let failure {
                    Section {
                        Label(failure, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(L10n.text("批次調整", "Batch Edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("取消", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("套用", "Apply"), action: beginConfirmation)
                        .fontWeight(.semibold)
                        .disabled(!canApply)
                        .accessibilityIdentifier("batch-apply")
                }
            }
            .onChange(of: edit) { _, _ in
                cachedReview = nil
                failure = nil
                if previewExpanded || (changeClassification && !changeDuration) { preparePreview() }
            }
            .onChange(of: selection) { _, _ in
                guard removalMode else { return }
                cachedRemoval = nil
                failure = nil
                if previewExpanded { preparePreview() }
            }
            .onChange(of: previewExpanded) { _, expanded in
                if expanded { preparePreview() }
            }
            .alert(confirmationTitle, isPresented: showingConfirmation, presenting: confirmation) { presented in
                switch presented {
                case let .apply(request):
                    Button(L10n.text("確認套用", "Confirm Apply")) { commit(request) }
                case let .removal(review, selected):
                    Button(L10n.text("移除", "Remove"), role: .destructive) { confirmRemoval(review, selected: selected) }
                }
                Button(L10n.text("取消", "Cancel"), role: .cancel) {}
            } message: { presented in
                switch presented {
                case let .apply(request):
                    Text(applySummary(request))
                case let .removal(review, _):
                    Text(L10n.text("將移除 \(review.ruleCount) 條規則（含子規則）和 \(review.eventCount) 筆尚未開始的事件。已開始的事件會保留。", "Rules to remove: \(review.ruleCount), including child rules. Future events to remove: \(review.eventCount). Events that have already started will be kept."))
                }
            }
        }
    }

    private func groupSelection(_ label: String, rules: [BatchRuleOption], isSubcategory: Bool) -> some View {
        let display = isSubcategory ? label : L10n.category(label)
        return selectionControl(display, ids: Set(rules.map(\.id)), isSubcategory: isSubcategory,
                         icon: isSubcategory ? "folder" : "folder.fill")
            .accessibilityLabel(L10n.text(
                "選擇\(isSubcategory ? "次類" : "分類")「\(label)」",
                "Select \(isSubcategory ? "subcategory" : "category") “\(display)”"
            ))
    }

    private func selectionControl(_ label: String, ids: Set<UUID>, isSubcategory: Bool = false,
                                  icon: String? = nil) -> some View {
        let selectedCount = ids.intersection(selection).count
        let checked = !ids.isEmpty && selectedCount == ids.count
        return Button {
            if checked { selection.subtract(ids) }
            else { selection.formUnion(ids) }
        } label: {
            HStack(spacing: 12) {
                SelectionMark(isSelected: checked)
                if let icon { Image(systemName: icon) }
                Text(label).fontWeight(isSubcategory ? .regular : .semibold)
                Spacer()
                Text(L10n.text("\(selectedCount)／\(ids.count)", "\(selectedCount)/\(ids.count)")).foregroundStyle(.secondary)
            }
            .padding(.leading, isSubcategory ? 16 : 0)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(checked ? [.isSelected] : [])
        .accessibilityValue(L10n.text("已選 \(selectedCount) 筆，共 \(ids.count) 筆", "\(selectedCount) of \(ids.count) selected"))
    }

    private func ruleSelection(_ rule: BatchRuleOption) -> some View {
        let checked = selection.contains(rule.id)
        return Button {
            if !selection.insert(rule.id).inserted { selection.remove(rule.id) }
        } label: {
            HStack(spacing: 12) {
                SelectionMark(isSelected: checked)
                VStack(alignment: .leading, spacing: 3) {
                    Text(rule.title).foregroundStyle(.primary)
                    if !rule.subtitle.isEmpty {
                        Text(rule.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .padding(.leading, rule.subcategory.isEmpty ? 8 : 24)
        .accessibilityAddTraits(checked ? [.isSelected] : [])
        .accessibilityIdentifier("batch-rule-option-\(rule.id.uuidString)")
    }

    private func applySummary(_ edit: BatchEdit) -> String {
        var lines: [String] = []
        if let classification = edit.classification {
            let category = L10n.category(classification.category)
            let path = classification.subcategory.isEmpty
                ? category : L10n.text("\(category)／\(classification.subcategory)", "\(category) / \(classification.subcategory)")
            lines.append(L10n.text("分類改為「\(path)」。", "Move to “\(path)”."))
        }
        if let duration = edit.duration {
            lines.append(L10n.text("重複期間改為 \(duration.caption)，不改動已開始的事件。", "Set repeat duration to \(duration.caption). Events that have already started will not change."))
        }
        return lines.joined(separator: "\n")
    }

    @ViewBuilder
    private var previewContent: some View {
        if removalMode {
            removalPreviewContent
        } else if let review = currentReview {
            switch review.result {
            case let .success(prepared):
                if edit?.duration != nil { BatchDurationReviewSections(review: prepared) }
                else if let edit, prepared.hasChanges { Text(applySummary(edit)) }
            case let .failure(error):
                Label(error.localizedDescription, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                Button(L10n.text("重試", "Try Again")) { preparePreview(force: true) }
            }
        } else if edit == nil {
            Text(L10n.text("請先選擇規則並填妥必要欄位。", "Select at least one rule and complete the required fields.")).foregroundStyle(.secondary)
        } else {
            Button(L10n.text("重試", "Try Again")) { preparePreview(force: true) }
        }
    }

    @ViewBuilder
    private var removalPreviewContent: some View {
        if let currentRemoval {
            switch currentRemoval.result {
            case let .success(review):
                Text(L10n.text("將移除的規則（\(review.ruleCount)）", "Rules to Remove (\(review.ruleCount))"))
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                ForEach(review.rules) { row in
                    Text(row.title)
                        .padding(.leading, CGFloat(min(row.depth, 6)) * 12)
                }
                Text(L10n.text("將移除的行事曆事件（\(review.eventCount)）", "Calendar Events to Remove (\(review.eventCount))"))
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if review.events.isEmpty {
                    Text(L10n.text("沒有尚未開始的事件可移除。", "No upcoming events to remove."))
                        .foregroundStyle(.secondary)
                }
                ForEach(review.events) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                        let zone = event.isAllDay
                            ? (TimeZone(identifier: "Asia/Taipei") ?? .current)
                            : (event.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current)
                        let day = L10n.date(event.start, timeZone: zone, includesWeekday: true)
                        Text(event.isAllDay ? day : "\(day) \(L10n.time(event.start, timeZone: zone))").monospacedDigit()
                        Text(event.calendarTitle)
                    }
                    .font(.footnote)
                    .accessibilityElement(children: .combine)
                }
                Text(L10n.text("已開始的事件不會移除。", "Events that have already started will be kept."))
                    .font(.footnote).foregroundStyle(.secondary)
            case let .failure(error):
                Label(error.localizedDescription, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                Button(L10n.text("重試", "Try Again")) { preparePreview(force: true) }
            }
        } else {
            Text(L10n.text("請先選擇要移除的規則。", "Select the rules to remove."))
                .foregroundStyle(.secondary)
        }
    }

    private func preparePreview(force: Bool = false) {
        if removalMode {
            guard !selection.isEmpty, force || currentRemoval == nil else { return }
            let selected = selection
            cachedRemoval = CachedRemoval(selection: selected, result: Result { try removalPreview(selected) })
            return
        }
        guard let edit, force || currentReview == nil else { return }
        cachedReview = CachedReview(edit: edit, result: Result { try preview(edit) })
    }

    private func beginConfirmation() {
        guard canApply else { return }
        failure = nil
        if removalMode {
            let selected = selection
            guard case let .success(reviewed)? = currentRemoval?.result else { return }
            do {
                let current = try removalPreview(selected)
                guard current == reviewed else {
                    showUpdatedRemoval(current, selected: selected)
                    return
                }
                confirmation = .removal(current, selected)
            } catch {
                preparePreview(force: true)
                previewExpanded = true
                failure = error.localizedDescription
            }
        } else if let edit {
            confirmation = .apply(edit)
        }
    }

    private func commit(_ request: BatchEdit) {
        guard let edit, edit == request else {
            failure = L10n.text("調整條件已變更，請重新確認。", "The batch settings have changed. Please confirm again.")
            return
        }
        do {
            guard case let .success(confirmed)? = currentReview?.result, confirmed.hasChanges else { return }
            let current = try preview(edit)
            guard confirmed.matches(current) else {
                cachedReview = CachedReview(edit: edit, result: .success(current))
                previewExpanded = true
                failure = L10n.text("行事曆內容已變更，請重新確認下面的預覽。", "Calendar has changed. Review the updated preview before confirming.")
                return
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
            guard removalMode, selected == selection else {
                failure = L10n.text("受影響的資料已變更，請重新按「套用」再確認。", "The affected rules or events have changed. Tap Apply and confirm again.")
                return
            }
            let current = try removalPreview(selected)
            guard current == proposed else {
                showUpdatedRemoval(current, selected: selected)
                return
            }
            try remove(selected, proposed)
            dismiss()
        } catch {
            preparePreview(force: true)
            previewExpanded = true
            failure = error.localizedDescription
        }
    }

    private func showUpdatedRemoval(_ review: BatchRemovalPreview, selected: Set<UUID>) {
        cachedRemoval = CachedRemoval(selection: selected, result: .success(review))
        previewExpanded = true
        failure = L10n.text("待移除的規則或事件已變更，請重新查看預覽，再按「套用」。",
                            "The rules or events to remove have changed. Review the updated preview before tapping Apply again.")
    }

}

struct CategoryEntryField: View {
    @Binding var selection: String
    let options: [String]
    let isSubcategory: Bool
    let fieldID: String
    let menuID: String

    private var label: String {
        isSubcategory ? L10n.text("次類", "Subcategory") : L10n.text("分類", "Category")
    }

    private var displayValue: Binding<String> {
        isSubcategory ? $selection : Binding(
            get: { L10n.category(selection) },
            set: { selection = $0 }
        )
    }

    var body: some View {
        let missing = !isSubcategory && selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(missing ? requiredFieldTint : Color.secondary)
                .accessibilityHidden(true)
            HStack(spacing: 2) {
                TextField(isSubcategory ? L10n.text("可留空", "Optional") : L10n.text("必填", "Required"),
                          text: displayValue)
                    .accessibilityLabel(isSubcategory ? label : L10n.text("\(label)（必填）", "\(label) (required)"))
                    .accessibilityIdentifier(fieldID)
                Menu {
                    if isSubcategory {
                        Button(L10n.text("不分次類", "No Subcategory")) { selection = "" }
                    }
                    ForEach(options, id: \.self) { option in
                        Button { selection = option } label: {
                            let title = isSubcategory ? option : L10n.category(option)
                            if selection == option {
                                Label(title, systemImage: "checkmark")
                            } else {
                                Text(title)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(options.isEmpty && !isSubcategory)
                .accessibilityLabel(L10n.text("選擇既有\(label)", "Choose an existing \(label.lowercased())"))
                .accessibilityIdentifier(menuID)
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
