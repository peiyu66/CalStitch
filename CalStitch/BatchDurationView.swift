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

struct BatchDurationReviewSections: View {
    let review: BatchDurationPreview

    var body: some View {
        Group {
            Text("新的截止日")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
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
            Text("行事曆變更")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
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
