import Contacts
import ContactsUI
import CryptoKit
import SwiftUI

struct BirthdayImportSource: Codable, Hashable {
    let contactID: String
    let isLunar: Bool
    let month: Int
    let day: Int
    let isLeapMonth: Bool
    let year: Int?
}

// Versioned, exact-match value. This is derived personal data, not anonymization.
enum BirthdayMatchToken {
    static func make(name: String, nickname: String?, isLunar: Bool, month: Int, day: Int,
                     isLeapMonth: Bool, year: Int?, accountID: String?, nameFields: [String]? = nil) -> String {
        func normalize(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        }
        // Keep the wire envelope readable by 34; version the fingerprint input instead.
        let nameParts = nameFields.map { ["CalStitch.birthday.v2"] + $0.map(normalize) }
            ?? ["CalStitch.birthday.v1", normalize(name)]
        let local = "l1:" + fingerprint(nameParts + [
            normalize(nickname ?? ""), isLunar ? "lunar" : "gregorian", String(month), String(day),
            isLunar && isLeapMonth ? "leap" : "regular", year.map(String.init) ?? ""
        ])
        return accountID.map { scoped(local, accountID: $0) } ?? local
    }

    static func scoped(_ value: String, accountID: String) -> String {
        guard value.hasPrefix("l1:") else { return value }
        return "a1:" + fingerprint(["CalStitch.birthday.account.v1", accountID, value])
    }

    static func isCloudValue(_ text: String) -> Bool {
        let payload = text.dropFirst(3)
        return text.hasPrefix("a1:") && payload.utf8.count == 64 &&
            payload.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func fingerprint(_ components: [String]) -> String {
        // UTF-8 length framing distinguishes nil placeholders, text, and adjacent fields.
        let encoded = components.map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(encoded.utf8)).map { String(format: "%02x", Int($0)) }.joined()
    }
}

enum BirthdayDuplicateStatus: Equatable {
    case available, imported, pending, possibleDuplicate

    var canSelect: Bool { self == .available || self == .possibleDuplicate }
}

struct BirthdayCandidate: Identifiable, Equatable, Sendable {
    struct Key: Hashable {
        let contactID: String
        let isLunar: Bool
    }

    let contactID: String
    var id: Key { Key(contactID: contactID, isLunar: isLunar) }
    let name: String
    var nickname: String? = nil
    let month: Int
    let day: Int
    let isLunar: Bool
    let isLeapMonth: Bool
    let year: Int?
    var nameFields: [String]? = nil

    func matchingToken(accountID: String?) -> String {
        BirthdayMatchToken.make(name: name, nickname: nickname, isLunar: isLunar, month: month, day: day,
                                isLeapMonth: isLeapMonth, year: year, accountID: accountID, nameFields: nameFields)
    }

    func legacyMatchingToken(accountID: String?) -> String {
        BirthdayMatchToken.make(name: name, nickname: nickname, isLunar: isLunar, month: month, day: day,
                                isLeapMonth: isLeapMonth, year: year, accountID: accountID)
    }

    private func chineseTitle(for text: String) -> String { text + (isLunar ? "農曆生日" : "生日") }
    private func englishTitle(for text: String) -> String { text + (isLunar ? "’s Lunar Birthday" : "’s Birthday") }

    func eventTitle(preferNickname: Bool) -> String {
        let text = preferNickname ? (nickname ?? name) : name
        return L10n.text(chineseTitle(for: text), englishTitle(for: text))
    }

    var duplicateTitles: Set<String> {
        Set([name, nickname].compactMap { $0 }.flatMap { [$0, chineseTitle(for: $0), englishTitle(for: $0)] })
    }

    var dateLabel: String {
        if isLunar {
            return L10n.text("農曆\(isLeapMonth ? "閏" : "")\(month) 月 \(day) 日",
                             isLeapMonth ? "Lunar leap month \(month), day \(day)" : "Lunar month \(month), day \(day)")
        }
        return L10n.text("西元 \(month) 月 \(day) 日", "Gregorian \(month)/\(day)")
    }

    static func extract(from contact: CNContact) -> [Self] {
        let formatterKeys = CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
        let formatted = contact.areKeysAvailable([formatterKeys]) ? CNContactFormatter.string(from: contact, style: .fullName) : nil
        let given = contact.isKeyAvailable(CNContactGivenNameKey) ? contact.givenName : ""
        let family = contact.isKeyAvailable(CNContactFamilyNameKey) ? contact.familyName : ""
        let organization = contact.isKeyAvailable(CNContactOrganizationNameKey) ? contact.organizationName : ""
        let name = [formatted ?? "", "\(family)\(given)", organization]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let name else { return [] }
        let trim = CharacterSet.whitespacesAndNewlines
        let middle = contact.isKeyAvailable(CNContactMiddleNameKey) ? contact.middleName : ""
        let parts = [given, middle, family].map { $0.trimmingCharacters(in: trim) }
        let nameFields: [String]?
        if contact.areKeysAvailable([CNContactGivenNameKey as NSString, CNContactMiddleNameKey as NSString,
                                     CNContactFamilyNameKey as NSString]), parts.contains(where: { !$0.isEmpty }) {
            nameFields = ["person"] + parts
        } else if contact.isKeyAvailable(CNContactOrganizationNameKey),
                  contact.areKeysAvailable([CNContactGivenNameKey as NSString, CNContactMiddleNameKey as NSString,
                                            CNContactFamilyNameKey as NSString]),
                  !organization.trimmingCharacters(in: trim).isEmpty {
            nameFields = ["organization", organization]
        } else {
            // Never fabricate a structured identity when the system picker withholds name keys.
            nameFields = nil
        }
        let rawNickname = contact.isKeyAvailable(CNContactNicknameKey)
            ? contact.nickname.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let nickname = rawNickname.isEmpty ? nil : rawNickname

        var candidates: [Self] = []
        if contact.isKeyAvailable(CNContactBirthdayKey), let birth = contact.birthday,
           let month = birth.month, let day = birth.day,
           (1...12).contains(month), day >= 1,
           day <= [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1] {
            candidates.append(.init(contactID: contact.identifier, name: name, nickname: nickname, month: month, day: day, isLunar: false, isLeapMonth: false, year: birth.year, nameFields: nameFields))
        }
        if contact.isKeyAvailable(CNContactNonGregorianBirthdayKey), let birth = contact.nonGregorianBirthday,
           birth.calendar?.identifier == .chinese,
           let month = birth.month, let day = birth.day,
           (1...12).contains(month), (1...30).contains(day) {
            candidates.append(.init(contactID: contact.identifier, name: name, nickname: nickname, month: month, day: day, isLunar: true, isLeapMonth: birth.isLeapMonth == true, year: birth.year, nameFields: nameFields))
        }
        return candidates
    }
}

struct BirthdayPickerSelection: Identifiable, Sendable {
    let id = UUID()
    let candidates: [BirthdayCandidate]
    let skipped: Int
    let groupName: String?

    init(_ contacts: [CNContact], groupName: String? = nil) {
        self.groupName = groupName
        let extracted = contacts.map(BirthdayCandidate.extract)
        var ids = Set<BirthdayCandidate.Key>()
        candidates = extracted.flatMap { $0 }.filter { ids.insert($0.id).inserted }
        skipped = extracted.filter(\.isEmpty).count
    }
}

struct BirthdayImportView: View {
    @ObservedObject var calendar: CalendarIntegration
    let categories: [BatchCategoryOption]
    let presetCalendarIDs: () -> [String: String]
    let status: (BirthdayCandidate) -> BirthdayDuplicateStatus
    let onImport: ([BirthdayCandidate], Int, String, String, String, Bool) async throws -> Void
    private let cameFromGroup: Bool

    @State private var explicitlySelectedCalendarID: String?
    @State private var errorMessage: String?
    @State private var calendarError: String?
    @State private var connecting = false
    @State private var isImporting = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var request: UUID?
    @State private var candidates: [BirthdayCandidate] = []
    @State private var selected = Set<BirthdayCandidate.Key>()
    @State private var explicitlyUnchecked = Set<BirthdayCandidate.Key>()
    @State private var preferNickname = true
    @State private var showWestern = true
    @State private var showLunar = true
    @State private var years = 5
    @State private var category = "生日"
    @State private var subcategory = ""
    @State private var skipped = 0

    init(selection: BirthdayPickerSelection,
         calendar: CalendarIntegration, categories: [BatchCategoryOption],
         presetCalendarIDs: @escaping () -> [String: String],
         status: @escaping (BirthdayCandidate) -> BirthdayDuplicateStatus,
         onImport: @escaping ([BirthdayCandidate], Int, String, String, String, Bool) async throws -> Void) {
        self.calendar = calendar
        self.categories = categories
        self.presetCalendarIDs = presetCalendarIDs
        self.status = status
        self.onImport = onImport
        cameFromGroup = selection.groupName != nil
        _subcategory = State(initialValue: selection.groupName ?? "")
        _candidates = State(initialValue: selection.candidates)
        _selected = State(initialValue: Set(selection.candidates.filter { status($0) == .available }.map(\.id)))
        _skipped = State(initialValue: selection.skipped)
    }

    private var visible: [BirthdayCandidate] {
        candidates.filter { $0.isLunar ? showLunar : showWestern }
    }

    private var bulkSelectable: Set<BirthdayCandidate.Key> {
        Set(visible.filter { status($0) == .available }.map(\.id))
    }

    private var needsIndividualReview: Bool {
        visible.contains {
            let current = status($0)
            return current == .possibleDuplicate
        }
    }

    private var importable: [BirthdayCandidate] {
        visible.filter { status($0).canSelect && selected.contains($0.id) }
    }

    private var targetID: String? {
        // Until explicitly selected, follow the current primary category by stable ID.
        // The observed CalendarIntegration validates availability as destinations load.
        explicitlySelectedCalendarID ?? presetCalendarIDs()[categoryName]
    }

    private var destination: CalendarDestination? {
        calendar.destinations.first { $0.id == targetID && $0.isWritable }
    }

    private var categoryName: String { category.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var subcategoryName: String { subcategory.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var availableSubcategories: [String] {
        categories.first { $0.name == categoryName }?.subcategories ?? []
    }

    private var canImport: Bool {
        calendar.hasFullAccess && !categoryName.isEmpty && !importable.isEmpty && destination != nil
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    } header: {
                        Text(L10n.text("無法匯入", "Unable to Import"))
                    }
                }
                Section {
                    capsulePicker([false, true], selection: $preferNickname, identifier: "birthday-name-preference",
                                  label: { $0 ? L10n.text("暱稱", "Nickname") : L10n.text("姓名", "Name") },
                                  optionIdentifier: { $0 ? "birthday-name-nickname" : "birthday-name-full" },
                                  softTint: { !$0 })
                } header: {
                    Text(L10n.text("生日名稱", "Birthday Title"))
                } footer: {
                    Text(L10n.text("沒有暱稱的聯絡人仍使用姓名。", "Contacts without a nickname still use their name."))
                }
                Section {
                    HStack(spacing: 28) {
                        checkbox(L10n.text("西元", "Gregorian"), checked: showWestern) { showWestern.toggle() }
                        checkbox(L10n.text("農曆", "Lunar"), checked: showLunar) { showLunar.toggle() }
                    }
                } header: {
                    Text(L10n.text("生日類型", "Birthday Calendars"))
                }

                Section {
                    if !visible.isEmpty { selectAllBirthdays }
                    if candidates.isEmpty {
                        Text(L10n.text("沒有可匯入的生日", "No birthdays to import")).foregroundStyle(.secondary)
                    } else if visible.isEmpty {
                        Text(L10n.text("沒有符合所選類型的生日", "No birthdays match the selected calendars")).foregroundStyle(.secondary)
                    }
                    ForEach(visible) { candidate in
                        let itemStatus = status(candidate)
                        let checked = itemStatus.canSelect && selected.contains(candidate.id)
                        Button {
                            if checked {
                                selected.remove(candidate.id)
                                explicitlyUnchecked.insert(candidate.id)
                            } else {
                                selected.insert(candidate.id)
                                explicitlyUnchecked.remove(candidate.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                SelectionMark(isSelected: checked)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(candidate.eventTitle(preferNickname: preferNickname)).foregroundStyle(.primary)
                                    Text(candidate.dateLabel).font(.subheadline).foregroundStyle(.secondary)
                                    if let note = statusText(itemStatus) {
                                        Text(note).font(.footnote)
                                            .foregroundStyle(itemStatus.canSelect ? Color.orange : Color.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!itemStatus.canSelect)
                        .accessibilityAddTraits(checked ? .isSelected : [])
                    }
                    if !cameFromGroup {
                        Button {
                            request = UUID()
                        } label: {
                            Label(L10n.text("再選聯絡人", "Select More Contacts"), systemImage: "person.badge.plus")
                        }
                    }
                } header: {
                    Text(L10n.text("要匯入的生日", "Birthdays to Import"))
                } footer: {
                    if needsIndividualReview {
                        Text(L10n.text("可能重複的項目，請個別確認後勾選。", "Review and select possible duplicates individually."))
                    }
                    if skipped > 0 {
                        Text(L10n.text("這次挑選有 \(skipped) 位聯絡人缺少可匯入的姓名或生日。",
                                      skipped == 1 ? "1 selected contact is missing a name or birthday."
                                                   : "\(skipped) selected contacts are missing a name or birthday."))
                    }
                }

                Section {
                    Stepper(L10n.text("重複期間：\(years) 年", "Repeat for \(years) \(years == 1 ? "year" : "years")"), value: $years, in: 1...999)
                } footer: {
                    Text(L10n.text("這個期間套用到本次匯入的生日規則。", "This duration applies to all the birthdays in this import."))
                }

                Section {
                    HStack(alignment: .top, spacing: 16) {
                        categoryField(L10n.text("分類", "Category"), value: $category, choices: categories.map(\.name))
                        categoryField(L10n.text("次類", "Subcategory"), value: $subcategory, choices: availableSubcategories, isSubcategory: true)
                    }
                } footer: {
                    Text(L10n.text("次類可留空，也可輸入聯絡人群組的名稱。", "Leave the subcategory blank or enter the contact list name."))
                }

                Section {
                    birthdayCalendarFields
                } footer: {
                    if !importable.isEmpty {
                        Text(L10n.text("按「匯入」會將選取的 \(importable.count) 筆生日加入指定行事曆。",
                                      "Tap Import to add \(importable.count) selected \(importable.count == 1 ? "birthday" : "birthdays") to the selected calendar."))
                    }
                }
            }
            .disabled(isImporting)
            .navigationTitle(L10n.text("匯入生日", "Import Birthdays"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("取消", "Cancel")) { dismiss() }
                        .disabled(isImporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("匯入", "Import"), action: performImport)
                        .fontWeight(.semibold)
                        .disabled(!canImport || isImporting)
                        .accessibilityIdentifier("confirm-birthday-import")
                }
            }
            .background {
                ContactPickerPresenter(request: request, onComplete: receive)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .interactiveDismissDisabled(isImporting)
    }

    @ViewBuilder
    private var birthdayCalendarFields: some View {
        if showCalendarConnectButton(calendar) {
            Button {
                connecting = true
                calendarError = nil
                Task {
                    defer { connecting = false }
                    do {
                        try await calendar.connectCalendars()
                    } catch {
                        calendarError = error.localizedDescription
                    }
                }
            } label: {
                if connecting {
                    ProgressView(L10n.text("正在連接行事曆…", "Connecting to Calendars…"))
                } else {
                    Label(L10n.text("連接行事曆", "Connect Calendars"), systemImage: "calendar.badge.plus")
                }
            }
            .disabled(connecting)
        } else if !calendar.destinations.isEmpty {
            let selected = calendar.destinations.first { $0.id == targetID }
            CalendarDestinationField(
                title: L10n.text("目的行事曆", "Destination Calendar"),
                selectedTitle: destination?.displayTitle
                    ?? selected.map { L10n.text("\($0.displayTitle)（唯讀）", "\($0.displayTitle) (read-only)") }
                    ?? (targetID == nil ? L10n.text("請選擇", "Choose a calendar") : L10n.text("已無法使用", "No longer available")),
                selectedID: targetID ?? "", isValid: destination != nil,
                destinations: calendar.destinations
            ) { explicitlySelectedCalendarID = $0 }
        }
        if let calendarError, calendar.destinations.isEmpty {
            Text(calendarError).font(.footnote).foregroundStyle(.red)
        }
        if !calendar.destinations.contains(where: \.isWritable) {
            Text(L10n.text("匯入前請先連接或選擇一個可寫入的行事曆。", "Connect or select a writable calendar before importing."))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func capsulePicker<Value: Hashable>(
        _ options: [Value], selection: Binding<Value>, identifier: String,
        label: @escaping (Value) -> String, optionIdentifier: @escaping (Value) -> String, softTint: @escaping (Value) -> Bool
    ) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 3))
            : AnyLayout(HStackLayout(spacing: 3))
        return layout {
            ForEach(options, id: \.self) { option in
                capsuleButton(label(option), isSelected: selection.wrappedValue == option,
                              softTint: softTint(option), identifier: optionIdentifier(option)) {
                    selection.wrappedValue = option
                }
            }
        }
        .padding(3)
        .background(Color(uiColor: .quaternarySystemFill), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func capsuleButton(_ title: String, isSelected: Bool, softTint: Bool, identifier: String,
                               action: @escaping () -> Void) -> some View {
        let shape = Capsule()
        return Button(action: action) {
            Text(title)
                .font(.body.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    if isSelected {
                        shape.fill(Color(uiColor: .systemBackground))
                            .overlay {
                                if softTint {
                                    shape.fill(Color(red: 0.38, green: 0.50, blue: 0.64).opacity(0.18))
                                }
                            }
                            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private func performImport() {
        guard canImport, !isImporting, let destination else { return }
        let selectedCandidates = importable
        let repeatYears = years
        let category = categoryName
        let subcategory = subcategoryName
        let useNickname = preferNickname
        errorMessage = nil
        isImporting = true
        Task { @MainActor in
            defer { isImporting = false }
            do {
                try await onImport(selectedCandidates, repeatYears, destination.id, category, subcategory, useNickname)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func statusText(_ status: BirthdayDuplicateStatus) -> String? {
        switch status {
        case .available: nil
        case .imported: L10n.text("已匯入", "Already imported")
        case .possibleDuplicate: L10n.text("可能重複", "Possible duplicate")
        case .pending: L10n.text("正在套用", "Applying")
        }
    }

    private func categoryField(_ title: String, value: Binding<String>, choices: [String], isSubcategory: Bool = false) -> some View {
        let displayValue = isSubcategory ? value : Binding(
            get: { L10n.category(value.wrappedValue) },
            set: { newValue in
                // Keep exact preset identities intact when presenting a translated label.
                guard newValue != L10n.category(value.wrappedValue) else { return }
                value.wrappedValue = newValue
            }
        )
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField(isSubcategory ? L10n.text("選填", "Optional") : L10n.text("必填", "Required"), text: displayValue)
                    .accessibilityLabel(title)
                if !choices.isEmpty {
                    Menu {
                        if isSubcategory {
                            Button(L10n.text("無次類", "No Subcategory")) { value.wrappedValue = "" }
                        }
                        ForEach(choices, id: \.self) { choice in
                            Button(isSubcategory ? choice : L10n.category(choice)) { value.wrappedValue = choice }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .frame(minWidth: 32, minHeight: 44)
                    }
                    .accessibilityLabel(isSubcategory ? L10n.text("選擇次類", "Choose a subcategory") : L10n.text("選擇分類", "Choose a category"))
                    .buttonStyle(.borderless)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectAllBirthdays: some View {
        let ids = bulkSelectable
        let selectedCount = ids.intersection(selected).count
        let checked = !ids.isEmpty && selectedCount == ids.count
        return Button {
            if checked {
                selected.subtract(ids)
                explicitlyUnchecked.formUnion(ids)
            } else {
                selected.formUnion(ids)
                explicitlyUnchecked.subtract(ids)
            }
        } label: {
            HStack(spacing: 12) {
                SelectionMark(isSelected: checked)
                Text(L10n.text("全選", "Select All")).fontWeight(.semibold)
                Spacer()
                Text(L10n.text("\(selectedCount)／\(ids.count)", "\(selectedCount)/\(ids.count)")).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .disabled(ids.isEmpty)
        .accessibilityAddTraits(checked ? .isSelected : [])
        .accessibilityValue(L10n.text("已選 \(selectedCount) 筆，共 \(ids.count) 筆", "\(selectedCount) of \(ids.count) selected"))
        .accessibilityIdentifier("birthday-select-all")
    }

    private func checkbox(_ title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                SelectionMark(isSelected: checked)
                Text(title).foregroundStyle(.primary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    private func receive(_ selection: BirthdayPickerSelection?) {
        request = nil
        guard let selection else { return }
        errorMessage = nil
        skipped = selection.skipped

        // A filter affects only presentation/import eligibility, not explicit selections.
        var known = Set(candidates.map(\.id))
        let retained = candidates.filter { !explicitlyUnchecked.contains($0.id) || !status($0).canSelect }
        let added = selection.candidates.filter { known.insert($0.id).inserted }
        candidates = retained + added
        selected.formIntersection(retained.map(\.id))
        selected.formUnion(added.filter { status($0) == .available }.map(\.id))
        explicitlyUnchecked.removeAll()
    }
}

struct ContactPickerPresenter: UIViewControllerRepresentable {
    let request: UUID?
    let onComplete: (BirthdayPickerSelection?) -> Void

    func makeUIViewController(context: Context) -> Host {
        Host()
    }

    func updateUIViewController(_ controller: Host, context: Context) {
        controller.request = request
        controller.onComplete = onComplete
        controller.schedulePresentation()
    }

    final class Host: UIViewController, CNContactPickerDelegate {
        var request: UUID?
        var onComplete: ((BirthdayPickerSelection?) -> Void)?
        private var handled: UUID?
        private var completing: UUID?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            schedulePresentation()
        }

        func schedulePresentation() {
            DispatchQueue.main.async { [weak self] in
                self?.presentIfNeeded()
            }
        }

        private func presentIfNeeded() {
            guard let request, request != handled, viewIfLoaded?.window != nil,
                  presentedViewController == nil else { return }
            if let transition = transitionCoordinator, transition.isAnimated,
               transition.animate(alongsideTransition: nil, completion: { [weak self] _ in self?.schedulePresentation() }) {
                return
            }
            handled = request
            let picker = CNContactPickerViewController()
            picker.delegate = self
            picker.displayedPropertyKeys = [CNContactBirthdayKey, CNContactNonGregorianBirthdayKey, CNContactNicknameKey]
            picker.predicateForSelectionOfContact = NSPredicate(value: true)
            present(picker, animated: true)
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            complete(BirthdayPickerSelection(contacts), afterDismissalOf: picker)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            complete(nil, afterDismissalOf: picker)
        }

        private func complete(_ selection: BirthdayPickerSelection?, afterDismissalOf picker: CNContactPickerViewController) {
            guard let handled, completing != handled else { return }
            completing = handled
            // ContactsUI may begin its own dismissal after returning from the delegate.
            DispatchQueue.main.async { [weak self, picker] in
                guard let self else { return }
                let didDismiss: () -> Void = { [weak self] in
                    guard let self, self.completing == handled else { return }
                    self.completing = nil
                    self.onComplete?(selection)
                }
                if picker.isBeingDismissed, let transition = picker.transitionCoordinator,
                   transition.animate(alongsideTransition: nil, completion: { _ in didDismiss() }) {
                    return
                }
                if picker.presentingViewController != nil {
                    picker.dismiss(animated: true, completion: didDismiss)
                } else {
                    didDismiss()
                }
            }
        }
    }
}

/// Only the intent to return to group lookup is persisted; no group or contact data.
@MainActor
enum BirthdayGroupSettingsReturn {
    private static let key = "birthday.pendingGroupSettingsReturn"

    static func begin(defaults: UserDefaults = .standard) -> UUID {
        let token = UUID()
        defaults.set(token.uuidString, forKey: key)
        return token
    }

    @discardableResult
    static func consume(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.string(forKey: key) != nil else { return false }
        defaults.removeObject(forKey: key)
        return true
    }

    static func clear(ifMatching token: UUID? = nil, defaults: UserDefaults = .standard) {
        if let token, defaults.string(forKey: key) != token.uuidString { return }
        defaults.removeObject(forKey: key)
    }
}

/// Group lookup is intentionally separate from the system picker. Only this flow
/// requests Contacts access; it reads birthdays solely from the chosen group.
struct BirthdayGroupImportView: View {
    @ObservedObject var calendar: CalendarIntegration
    let categories: [BatchCategoryOption]
    let presetCalendarIDs: () -> [String: String]
    let status: (BirthdayCandidate) -> BirthdayDuplicateStatus
    let onChoosePeople: () -> Void
    let onImport: ([BirthdayCandidate], Int, String, String, String, Bool) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var state: State = .intro
    @State private var task: Task<Void, Never>?
    @State private var selection: BirthdayPickerSelection?
    @State private var settingsOpenFailed = false

    private enum State {
        case intro, loading, settings, restricted, groups([GroupOption]), lookupFailed
    }

    var body: some View {
        Group {
            if let selection {
                BirthdayImportView(selection: selection, calendar: calendar, categories: categories,
                                   presetCalendarIDs: presetCalendarIDs, status: status, onImport: onImport)
            } else {
                NavigationStack {
                    List {
                        switch state {
                        case .intro:
                            Text(L10n.text(
                                "按「讀取聯絡人群組」後，請在系統授權視窗選擇「完整取用權限」。",
                                "Tap Load Contact Lists, then choose Full Access in the system prompt."
                            ))
                            Text(L10n.text(
                                "CalStitch 只會讀取所選群組成員的姓名、暱稱和生日。若不想授予完整取用權限，可以改用個別選人。",
                                "CalStitch reads only the names, nicknames, and birthdays of people in the list you select. If you prefer not to grant full access, you can select people individually instead."
                            ))
                            .foregroundStyle(.secondary)
                            Button(L10n.text("讀取聯絡人群組", "Load Contact Lists")) { loadGroups(allowPrompt: true) }
                        case .loading:
                            ProgressView(L10n.text("讀取中…", "Loading…"))
                        case .settings:
                            Text(L10n.text("群組匯入需要通訊錄的「完整取用權限」，請到「設定」變更權限。", "Importing contact lists requires Full Access to Contacts. You can change this in Settings."))
                            Button(L10n.text("開啟設定", "Open Settings"), action: openSettings)
                            if settingsOpenFailed {
                                Text(L10n.text("無法開啟設定，請手動到設定變更權限。", "Could not open Settings. Open Settings directly to change access."))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        case .restricted:
                            Text(L10n.text("這台裝置限制了通訊錄存取，無法讀取群組。請回上一頁使用個別選人。", "Contacts access is restricted on this device. Go back and select people individually."))
                        case .groups(let groups):
                            if groups.isEmpty {
                                Text(L10n.text("找不到通訊錄群組。可改用個別選人。", "No contact lists found. You can select people individually instead."))
                            } else {
                                ForEach(groups) { group in
                                    Button { loadSelection(for: group) } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(group.name)
                                            if let detail = group.detail {
                                                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        case .lookupFailed:
                            Text(L10n.text("無法讀取通訊錄群組或成員。請檢查權限後重試。", "Could not read contact lists or their members. Check access and try again."))
                            Button(L10n.text("重試", "Try Again")) { loadGroups() }
                        }
                        Section {
                            Button(L10n.text("改用個別選人", "Select People Individually")) {
                                BirthdayGroupSettingsReturn.clear()
                                task?.cancel()
                                onChoosePeople()
                            }
                        }
                    }
                    .navigationTitle(L10n.text("從群組匯入生日", "Import Birthdays from a List"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.text("取消", "Cancel")) {
                                BirthdayGroupSettingsReturn.clear()
                                task?.cancel()
                                dismiss()
                            }
                        }
                    }
                }
                .task {
                    if case .intro = state,
                       CNContactStore.authorizationStatus(for: .contacts) != .notDetermined {
                        loadGroups()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active, case .settings = state else { return }
                    let returnedFromSettings = BirthdayGroupSettingsReturn.consume()
                    if returnedFromSettings || CNContactStore.authorizationStatus(for: .contacts) == .authorized {
                        settingsOpenFailed = false
                        loadGroups()
                    }
                }
                .onDisappear { task?.cancel() }
            }
        }
    }

    private func openSettings() {
        settingsOpenFailed = false
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            BirthdayGroupSettingsReturn.clear()
            settingsOpenFailed = true
            return
        }
        let token = BirthdayGroupSettingsReturn.begin()
        UIApplication.shared.open(url) { didOpen in
            guard !didOpen else { return }
            BirthdayGroupSettingsReturn.clear(ifMatching: token)
            settingsOpenFailed = true
        }
    }

    private func loadGroups(allowPrompt: Bool = false) {
        task?.cancel()
        state = .loading
        task = Task { @MainActor in
            do {
                if allowPrompt, CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
                    _ = try await CNContactStore().requestAccess(for: .contacts)
                }
                guard !Task.isCancelled else { return }
                switch CNContactStore.authorizationStatus(for: .contacts) {
                case .authorized:
                    let groups = try await Task.detached(priority: .userInitiated) {
                        try Self.readGroups()
                    }.value
                    guard !Task.isCancelled else { return }
                    state = .groups(groups)
                case .restricted:
                    state = .restricted
                default:
                    state = .settings // Includes the iOS 18 limited-access mode.
                }
            } catch {
                guard !Task.isCancelled else { return }
                state = CNContactStore.authorizationStatus(for: .contacts) == .authorized ? .lookupFailed : .settings
            }
        }
    }

    private func loadSelection(for group: GroupOption) {
        task?.cancel()
        state = .loading
        task = Task { @MainActor in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try Self.readMembers(of: group)
                }.value
                guard !Task.isCancelled else { return }
                selection = result
            } catch {
                guard !Task.isCancelled else { return }
                state = CNContactStore.authorizationStatus(for: .contacts) == .authorized ? .lookupFailed : .settings
            }
        }
    }

    private struct GroupOption: Identifiable, Sendable {
        let id: String
        let name: String
        let detail: String?
    }

    nonisolated private static func readGroups() throws -> [GroupOption] {
        let store = CNContactStore()
        let groups = try store.groups(matching: nil).sorted { lhs, rhs in
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.identifier < rhs.identifier : order == .orderedAscending
        }
        let duplicateNames = Set(Dictionary(grouping: groups, by: \.name).filter { $0.value.count > 1 }.keys)
        var sourceNames: [String: String] = [:]
        if !duplicateNames.isEmpty, let containers = try? store.containers(matching: nil) {
            for container in containers {
                let name = container.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let predicate = CNGroup.predicateForGroupsInContainer(withIdentifier: container.identifier)
                for group in (try? store.groups(matching: predicate)) ?? [] where duplicateNames.contains(group.name) {
                    sourceNames[group.identifier] = name
                }
            }
        }

        let distinct = groups.map { group in
            GroupOption(id: group.identifier, name: group.name, detail: sourceNames[group.identifier])
        }
        return distinct.map { group in
            let matches = distinct.filter { $0.name == group.name && $0.detail == group.detail }
            guard matches.count > 1, let index = matches.firstIndex(where: { $0.id == group.id }) else { return group }
            return GroupOption(id: group.id, name: group.name, detail: "\(group.detail ?? L10n.text("同名群組", "Same-name list")) · \(index + 1)")
        }
    }

    nonisolated private static func readMembers(of group: GroupOption) throws -> BirthdayPickerSelection {
        let store = CNContactStore()
        let keys: [any CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactGivenNameKey as NSString, CNContactMiddleNameKey as NSString, CNContactFamilyNameKey as NSString,
            CNContactOrganizationNameKey as NSString, CNContactNicknameKey as NSString,
            CNContactBirthdayKey as NSString, CNContactNonGregorianBirthdayKey as NSString
        ]
        let predicate = CNContact.predicateForContactsInGroup(withIdentifier: group.id)
        return BirthdayPickerSelection(try store.unifiedContacts(matching: predicate, keysToFetch: keys),
                                       groupName: group.name)
    }
}
