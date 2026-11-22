import SwiftUI

struct BatchDurationRule: Identifiable, Equatable {
    let id: UUID
    let title: String
    let cutoff: Date
    let isDraft: Bool
}

struct BatchDurationPreview {
    let rules: [BatchDurationRule]
    let changes: [CalendarChange]

    func matches(_ other: Self) -> Bool {
        rules == other.rules && changes.count == other.changes.count &&
        zip(changes, other.changes).allSatisfy { lhs, rhs in
            lhs.id == rhs.id && lhs.verb == rhs.verb && lhs.title == rhs.title && lhs.date == rhs.date
        }
    }
}

struct BatchDurationView: View {
    let selectedCount: Int
    let preview: (Int) throws -> BatchDurationPreview
    let apply: (Int) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var years = 1
    @State private var review: BatchDurationPreview?
    @State private var failure: String?
    @State private var confirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("已選規則", value: "\(selectedCount) 條")
                    Stepper("重複期間：\(years) 年", value: $years, in: 1...100)
                    Button("預覽變更", action: prepare)
                        .disabled(selectedCount == 0)
                } footer: {
                    Text("只變更重複期間。每條規則從原本的起始日換算新的截止日。")
                }
                if let failure {
                    Section {
                        Label(failure, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    } header: {
                        Text("無法完成")
                    }
                }
                if let review {
                    Section("新的截止日") {
                        ForEach(review.rules) { rule in
                            LabeledContent {
                                Text(dateCaption(rule.cutoff)).monospacedDigit()
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(rule.title)
                                    if rule.isDraft {
                                        Text("待套用規則，只更改草稿").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    Section("行事曆變更") {
                        if review.changes.isEmpty {
                            Text("沒有需要變更的行程").foregroundStyle(.secondary)
                        } else {
                            ForEach(review.changes) { change in
                                LabeledContent(change.title, value: "\(change.verb) · \(dateCaption(change.date))")
                            }
                        }
                    }
                }
            }
            .navigationTitle("更改重複期間")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("套用") { confirm = true }
                        .fontWeight(.semibold)
                        .disabled(review == nil)
                }
            }
            .onChange(of: years) { _, _ in
                review = nil
                failure = nil
            }
            .confirmationDialog("套用至 \(selectedCount) 條規則？", isPresented: $confirm, titleVisibility: .visible) {
                Button("確認套用", action: commit)
                Button("取消", role: .cancel) {}
            } message: {
                Text("只更改重複期間，不改動已開始的行程。")
            }
        }
    }

    private func prepare() {
        do {
            review = try preview(years)
            failure = nil
        } catch {
            review = nil
            failure = error.localizedDescription
        }
    }

    private func commit() {
        guard let confirmedReview = review else { return }
        do {
            let current = try preview(years)
            guard confirmedReview.matches(current) else {
                self.review = current
                failure = "行事曆內容已變更，請重新確認下面的預覽。"
                return
            }
            try apply(years)
            dismiss()
        } catch {
            review = nil
            failure = error.localizedDescription
        }
    }

}
