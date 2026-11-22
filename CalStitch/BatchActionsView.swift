import SwiftUI

struct BatchCategoryOption {
    let name: String
    let subcategories: [String]
}

struct BatchRemovalPreview: Equatable {
    let ruleCount: Int
    let eventCount: Int
}

struct BatchActionsView: View {
    let selectedCount: Int
    let categories: [BatchCategoryOption]
    let durationPreview: (Int) throws -> BatchDurationPreview
    let durationApply: (Int) throws -> Void
    let move: (String, String) throws -> Void
    let removalPreview: () throws -> BatchRemovalPreview
    let remove: () throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showDuration = false
    @State private var showMove = false
    @State private var removal: BatchRemovalPreview?
    @State private var showRemoval = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("已選規則", value: "\(selectedCount) 條")
                }
                Section {
                    Button {
                        showDuration = true
                    } label: {
                        Label("更改重複期間", systemImage: "calendar.badge.clock")
                    }
                    Button {
                        showMove = true
                    } label: {
                        Label("更改分類／次類", systemImage: "folder")
                    }
                }
                Section {
                    Button(role: .destructive, action: prepareRemoval) {
                        Label("整批移除", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("一併移除已選規則、關聯子規則，以及它們建立且尚未開始的事件。")
                }
            }
            .navigationTitle("批次調整")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $showDuration, onDismiss: { if completed { dismiss() } }) {
                BatchDurationView(selectedCount: selectedCount, preview: durationPreview) { years in
                    try durationApply(years)
                    completed = true
                }
            }
            .sheet(isPresented: $showMove, onDismiss: { if completed { dismiss() } }) {
                BatchMoveCategoryView(selectedCount: selectedCount, categories: categories) { category, subcategory in
                    try move(category, subcategory)
                    completed = true
                }
            }
            .confirmationDialog("確定整批移除？", isPresented: $showRemoval, titleVisibility: .visible, presenting: removal) { proposed in
                Button("移除 \(proposed.ruleCount) 條規則", role: .destructive) { confirmRemoval(proposed) }
                Button("取消", role: .cancel) {}
            } message: { proposed in
                Text("將移除 \(proposed.ruleCount) 條規則（含子規則）和 \(proposed.eventCount) 筆尚未開始的事件。已開始的事件會保留。")
            }
            .alert("無法完成操作", isPresented: Binding(
                get: { failure != nil }, set: { if !$0 { failure = nil } }
            )) {
                Button("好", role: .cancel) { failure = nil }
            } message: { Text(failure ?? "") }
        }
    }

    @State private var completed = false

    private func prepareRemoval() {
        do {
            removal = try removalPreview()
            showRemoval = true
        } catch {
            failure = error.localizedDescription
        }
    }

    private func confirmRemoval(_ proposed: BatchRemovalPreview) {
        do {
            let latest = try removalPreview()
            guard latest == proposed else {
                failure = "受影響的資料已變更，請重新選擇「整批移除」再確認。"
                return
            }
            try remove()
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}

private struct BatchMoveCategoryView: View {
    let selectedCount: Int
    let categories: [BatchCategoryOption]
    let move: (String, String) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var category = ""
    @State private var subcategory = ""
    @State private var failure: String?

    private var categoryName: String { category.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var subcategoryName: String { subcategory.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var availableSubcategories: [String] {
        categories.first { $0.name == categoryName }?.subcategories ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    let layout = textSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                    layout {
                        entry("分類", placeholder: "必填", text: $category, options: categories.map(\.name))
                        entry("次類", placeholder: "可留空", text: $subcategory, options: availableSubcategories, canClear: true)
                    }
                } header: {
                    Text("移到")
                } footer: {
                    Text("將移動 \(selectedCount) 條規則及其子規則，不修改行事曆。次類留空會把規則直接放在分類下。")
                }
                if let failure {
                    Label(failure, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                }
            }
            .navigationTitle("更改分類／次類")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("移動") {
                        do {
                            try move(categoryName, subcategoryName)
                            dismiss()
                        } catch {
                            failure = error.localizedDescription
                        }
                    }
                    .disabled(categoryName.isEmpty)
                }
            }
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
