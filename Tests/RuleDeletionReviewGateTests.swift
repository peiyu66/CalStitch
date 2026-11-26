@main
struct RuleDeletionReviewGateTests {
    struct Preview: Equatable {
        let identity: String
        let privateNotes: String
        let revision: Int
    }

    static func main() {
        let original = Preview(identity: "synthetic-rule:0", privateNotes: "original", revision: 1)
        let changed = Preview(identity: original.identity, privateNotes: "notes-only edit", revision: 2)
        var review = RuleDeletionReviewGate<Preview>()
        var attempted: [Preview] = []
        func confirm(_ availability: RuleDeletionAvailability, error: Bool = false) {
            if let accepted = review.begin(availability, hasError: error) { attempted.append(accepted) }
        }

        confirm(.ready)
        precondition(attempted.isEmpty)
        review.accept(original)
        review.invalidate()
        confirm(.checking)
        confirm(.readFailed("network"))
        confirm(.ready) // the read ended, but no fresh preview yet
        confirm(.ready, error: true)
        precondition(attempted.isEmpty && review.preview == original && review.canDismiss)

        // Cloud became available; even with a different event fingerprint no
        // queued click runs, and the old fingerprint is no longer pending.
        review.accept(changed)
        precondition(review.changed && attempted.isEmpty)
        confirm(.ready)
        confirm(.ready)
        precondition(attempted == [changed] && review.submitting && !review.canDismiss && !review.changed)
        review.end()
        precondition(review.canDismiss)
        print("Single-rule deletion review gate: busy, read failure, changed fingerprint, explicit confirm, duplicate-submit guard")
    }
}
