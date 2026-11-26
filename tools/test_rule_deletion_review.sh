#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
temporary="$(mktemp -d /tmp/calstitch-delete-review.XXXXXX)"
trap 'rm -rf "$temporary"' EXIT
sed -n '/^\/\/ MARK: Single-rule deletion confirmation$/,/^\/\/ MARK: Single-rule deletion presentation$/{ /^\/\/ MARK: Single-rule deletion presentation$/!p; }' \
    CalStitch/CalStitchApp.swift > "$temporary/ReviewGate.swift"
swiftc -module-cache-path "$temporary/modules" "$temporary/ReviewGate.swift" Tests/RuleDeletionReviewGateTests.swift -o "$temporary/review"
"$temporary/review"
