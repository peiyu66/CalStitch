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
    let hasChanges: Bool

    func matches(_ other: Self) -> Bool {
        hasChanges == other.hasChanges && rules == other.rules && changes.count == other.changes.count &&
        zip(changes, other.changes).allSatisfy { lhs, rhs in
            lhs.id == rhs.id && lhs.ruleID == rhs.ruleID && lhs.verb == rhs.verb && lhs.title == rhs.title && lhs.date == rhs.date
        }
    }
}

struct BatchDurationReviewSections: View {
    let review: BatchDurationPreview

    var body: some View {
        let changesByRule = Dictionary(grouping: review.changes, by: \.ruleID)
        let merged = Dictionary(uniqueKeysWithValues: review.rules.compactMap { rule in
            changesByRule[rule.id]?.first(where: { $0.title == rule.title }).map { ($0.id, rule) }
        })
        let mergedRuleIDs = Set(merged.values.map(\.id))
        let separateRules = review.rules.filter { !mergedRuleIDs.contains($0.id) }
        return Group {
            if !separateRules.isEmpty {
                Text(L10n.text("新的截止日", "New End Dates"))
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(separateRules) { rule in
                LabeledContent {
                    Text(dateCaption(rule.cutoff)).monospacedDigit()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(rule.title)
                        if rule.isDraft {
                            Text(L10n.text("待套用規則，只更改草稿", "This rule is a draft. Only the draft will change.")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text(L10n.text("行事曆變更", "Calendar Changes"))
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if review.changes.isEmpty {
                Text(L10n.text("沒有需要變更的行程", "No calendar events to change")).foregroundStyle(.secondary)
            } else {
                ForEach(review.changes) { change in
                    LabeledContent {
                        Text("\(change.verb) · \(dateCaption(change.date))")
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(change.title)
                            if let rule = merged[change.id] {
                                Text(L10n.text("新截止日：\(dateCaption(rule.cutoff))", "New End Date: \(dateCaption(rule.cutoff))"))
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                if rule.isDraft {
                                    Text(L10n.text("待套用規則，只更改草稿", "This rule is a draft. Only the draft will change."))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
