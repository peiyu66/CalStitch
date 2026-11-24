#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
temporary="$(mktemp -d /tmp/calstitch-cloud-contract.XXXXXX)"
trap 'rm -rf "$temporary"' EXIT
# Use the same production calendar/rule types and CloudKit coordinator, without
# linking the iOS UIKit/SwiftUI app into this macOS-only contract executable.
{
    echo 'import Foundation'
    echo 'struct RuleAppearance: Codable, Hashable {}'
    sed -n '/^struct BirthdayImportSource:/,/^}/p' CalStitch/BirthdayImportView.swift
    sed -n '/^private let ruleZone/,/^func categoryCalendarPresets/{ /^func categoryCalendarPresets/!p; }' CalStitch/CalStitchApp.swift
    sed -n '/^struct CalendarSyncDestination:/,/^struct CalendarChange:/{ /^struct CalendarChange:/!p; }' CalStitch/CalendarIntegration.swift
} > "$temporary/Models.swift"
swiftc -module-cache-path "$temporary/modules" "$temporary/Models.swift" CalStitch/{L10n,RuleEngine,SolarTerms,RuleCloudSync}.swift     Tests/CloudRuleSyncContract.swift -o "$temporary/cloud"
"$temporary/cloud"
swiftc -module-cache-path "$temporary/modules" "$temporary/Models.swift" CalStitch/{L10n,RuleEngine,SolarTerms}.swift     Tests/LunarRuleTests.swift -o "$temporary/lunar"
"$temporary/lunar"
swiftc -module-cache-path "$temporary/modules" CalStitch/{L10n,SolarTerms}.swift Tests/SolarTermsTests.swift -o "$temporary/solar"
"$temporary/solar"
