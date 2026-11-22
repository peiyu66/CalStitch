import Contacts
import ContactsUI
import SwiftUI

struct BirthdayImportSource: Codable, Hashable {
    let contactID: String
    let isLunar: Bool
    let month: Int
    let day: Int
    let isLeapMonth: Bool
    let year: Int?
}

enum BirthdayDuplicateStatus: Equatable {
    case available, imported, possibleDuplicate, changed
}

struct BirthdayCandidate: Identifiable, Equatable {
    struct Key: Hashable {
        let contactID: String
        let isLunar: Bool
    }

    let contactID: String
    var id: Key { Key(contactID: contactID, isLunar: isLunar) }
    let name: String
    let month: Int
    let day: Int
    let isLunar: Bool
    let isLeapMonth: Bool
    let year: Int?

    var source: BirthdayImportSource {
        .init(contactID: contactID, isLunar: isLunar, month: month, day: day, isLeapMonth: isLeapMonth, year: year)
    }

    var dateLabel: String {
        if isLunar {
            return "農曆\(isLeapMonth ? "閏" : "")\(month) 月 \(day) 日"
        }
        return "西元 \(month) 月 \(day) 日"
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

        var candidates: [Self] = []
        if contact.isKeyAvailable(CNContactBirthdayKey), let birth = contact.birthday,
           let month = birth.month, let day = birth.day,
           (1...12).contains(month), day >= 1,
           day <= [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1] {
            candidates.append(.init(contactID: contact.identifier, name: name, month: month, day: day, isLunar: false, isLeapMonth: false, year: birth.year))
        }
        if contact.isKeyAvailable(CNContactNonGregorianBirthdayKey), let birth = contact.nonGregorianBirthday,
           birth.calendar?.identifier == .chinese,
           let month = birth.month, let day = birth.day,
           (1...12).contains(month), (1...30).contains(day) {
            candidates.append(.init(contactID: contact.identifier, name: name, month: month, day: day, isLunar: true, isLeapMonth: birth.isLeapMonth == true, year: birth.year))
        }
        return candidates
    }
}

struct BirthdayPickerSelection: Identifiable {
    let id = UUID()
    let candidates: [BirthdayCandidate]
    let skipped: Int

    init(_ contacts: [CNContact]) {
        let extracted = contacts.map(BirthdayCandidate.extract)
        var ids = Set<BirthdayCandidate.Key>()
        candidates = extracted.flatMap { $0 }.filter { ids.insert($0.id).inserted }
        skipped = extracted.filter(\.isEmpty).count
    }
}

struct BirthdayImportView: View {
    @ObservedObject var calendar: CalendarIntegration
    let categories: [BatchCategoryOption]
    let status: (BirthdayCandidate) -> BirthdayDuplicateStatus
    let onImport: ([BirthdayCandidate], Int, String?, String, String) throws -> Void

    private enum ImportMode: String, CaseIterable {
        case draft = "草稿"
        case apply = "匯入後套用"
    }

    @State private var mode: ImportMode = .draft
    @State private var targetID: String? = nil
    @State private var errorMessage: String?
    @State private var calendarError: String?
    @State private var connecting = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var request: UUID?
    @State private var candidates: [BirthdayCandidate] = []
    @State private var selected = Set<BirthdayCandidate.Key>()
    @State private var explicitlyUnchecked = Set<BirthdayCandidate.Key>()
    @State private var showWestern = true
    @State private var showLunar = true
    @State private var years = 5
    @State private var category = "生日"
    @State private var subcategory = ""
    @State private var skipped = 0

    init(selection: BirthdayPickerSelection,
         calendar: CalendarIntegration, categories: [BatchCategoryOption],
         status: @escaping (BirthdayCandidate) -> BirthdayDuplicateStatus,
         onImport: @escaping ([BirthdayCandidate], Int, String?, String, String) throws -> Void) {
        self.calendar = calendar
        self.categories = categories
        self.status = status
        self.onImport = onImport
        _candidates = State(initialValue: selection.candidates)
        _selected = State(initialValue: Set(selection.candidates.filter { status($0) == .available }.map(\.id)))
        _skipped = State(initialValue: selection.skipped)
    }

    private var visible: [BirthdayCandidate] {
        candidates.filter { $0.isLunar ? showLunar : showWestern }
    }

    private var importable: [BirthdayCandidate] {
        visible.filter { status($0) != .imported && selected.contains($0.id) }
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
        !categoryName.isEmpty && !importable.isEmpty && (mode == .draft || destination != nil)
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    } header: {
                        Text("無法匯入")
                    }
                }
                Section {
                    HStack(spacing: 28) {
                        checkbox("西元", checked: showWestern) { showWestern.toggle() }
                        checkbox("農曆", checked: showLunar) { showLunar.toggle() }
                    }
                } header: {
                    Text("生日類型")
                }

                Section {
                    if candidates.isEmpty {
                        Text("沒有可匯入的生日").foregroundStyle(.secondary)
                    } else if visible.isEmpty {
                        Text("沒有符合所選類型的生日").foregroundStyle(.secondary)
                    }
                    ForEach(visible) { candidate in
                        let itemStatus = status(candidate)
                        let checked = itemStatus != .imported && selected.contains(candidate.id)
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
                                checkIcon(checked)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(candidate.name).foregroundStyle(.primary)
                                    Text(candidate.dateLabel).font(.subheadline).foregroundStyle(.secondary)
                                    if let note = statusText(itemStatus) {
                                        Text(note).font(.footnote)
                                            .foregroundStyle(itemStatus == .imported ? Color.secondary : Color.orange)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(itemStatus == .imported)
                        .accessibilityAddTraits(checked ? .isSelected : [])
                    }
                    Button {
                        request = UUID()
                    } label: {
                        Label("再選聯絡人", systemImage: "person.badge.plus")
                    }
                } header: {
                    Text("要匯入的生日")
                } footer: {
                    if skipped > 0 {
                        Text("這次挑選有 \(skipped) 位聯絡人缺少可匯入的姓名或生日。")
                    }
                }

                Section {
                    Stepper("重複期間：\(years) 年", value: $years, in: 1...999)
                } footer: {
                    Text("這個期間套用到本次匯入的生日規則。")
                }

                Section {
                    HStack(alignment: .top, spacing: 16) {
                        categoryField("分類", value: $category, choices: categories.map(\.name))
                        categoryField("次類", value: $subcategory, choices: availableSubcategories)
                    }
                } footer: {
                    Text("次類可留空，也可輸入聯絡人群組的名稱。")
                }

                Section("匯入方式") {
                    if dynamicTypeSize.isAccessibilitySize {
                        importModePicker.pickerStyle(.menu)
                    } else {
                        importModePicker.pickerStyle(.segmented)
                    }
                    if mode == .draft {
                        Text("只建立草稿，不會寫入行事曆。")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        birthdayCalendarFields
                    }
                    Button {
                        performImport()
                    } label: {
                        Text(mode == .draft
                             ? "匯入 \(importable.count) 筆草稿"
                             : "匯入並套用 \(importable.count) 筆")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canImport)
                    .accessibilityIdentifier("confirm-birthday-import")
                }
            }
            .navigationTitle("匯入生日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .background {
                ContactPickerPresenter(request: request, onComplete: receive)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
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
                    ProgressView("正在連接行事曆…")
                } else {
                    Label("連接行事曆", systemImage: "calendar.badge.plus")
                }
            }
            .disabled(connecting)
        } else if !calendar.destinations.isEmpty {
            let selected = calendar.destinations.first { $0.id == targetID }
            CalendarDestinationField(
                title: "目的行事曆",
                selectedTitle: destination?.displayTitle
                    ?? selected.map { "\($0.displayTitle)（唯讀）" }
                    ?? (targetID == nil ? "請選擇" : "已無法使用"),
                selectedID: targetID ?? "", isValid: destination != nil,
                destinations: calendar.destinations
            ) { targetID = $0 }
        }
        if let calendarError, calendar.destinations.isEmpty {
            Text(calendarError).font(.footnote).foregroundStyle(.red)
        }
        if !calendar.destinations.contains(where: \.isWritable) {
            Text("沒有可寫入的行事曆時，仍可匯入草稿。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var importModePicker: some View {
        Picker("匯入方式", selection: $mode) {
            ForEach(ImportMode.allCases, id: \.self) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .accessibilityIdentifier("birthday-import-mode")
    }

    private func performImport() {
        guard canImport else { return }
        errorMessage = nil
        do {
            let target = mode == .apply ? destination?.id : nil
            try onImport(importable, years, target, categoryName, subcategoryName)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func statusText(_ status: BirthdayDuplicateStatus) -> String? {
        switch status {
        case .available: nil
        case .imported: "已匯入"
        case .possibleDuplicate: "可能重複"
        case .changed: "生日與舊規則不同，匯入不會覆寫舊規則"
        }
    }

    private func categoryField(_ title: String, value: Binding<String>, choices: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField(title == "次類" ? "選填" : "必填", text: value)
                    .accessibilityLabel(title)
                if !choices.isEmpty {
                    Menu {
                        if title == "次類" {
                            Button("無次類") { value.wrappedValue = "" }
                        }
                        ForEach(choices, id: \.self) { choice in
                            Button(choice) { value.wrappedValue = choice }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .frame(minWidth: 32, minHeight: 44)
                    }
                    .accessibilityLabel("選擇\(title)")
                    .buttonStyle(.borderless)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func checkIcon(_ checked: Bool) -> some View {
        Image(systemName: checked ? "checkmark.square.fill" : "square")
            .font(.title3)
            .foregroundStyle(checked ? Color.accentColor : .secondary)
            .accessibilityHidden(true)
    }

    private func checkbox(_ title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                checkIcon(checked)
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
        let retained = candidates.filter { !explicitlyUnchecked.contains($0.id) || status($0) == .imported }
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
            picker.displayedPropertyKeys = [CNContactBirthdayKey, CNContactNonGregorianBirthdayKey]
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
