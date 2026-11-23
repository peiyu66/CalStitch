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

struct BirthdayCandidate: Identifiable, Equatable, Sendable {
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

    var eventTitle: String { name + (isLunar ? "農曆生日" : "生日") }

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
    let onImport: ([BirthdayCandidate], Int, String, Bool, String, String) throws -> Void
    private let cameFromGroup: Bool

    private enum ImportMode: String, CaseIterable {
        case draft = "草稿"
        case apply = "匯入後套用"
    }

    @State private var mode: ImportMode = .draft
    @State private var explicitlySelectedCalendarID: String?
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
         presetCalendarIDs: @escaping () -> [String: String],
         status: @escaping (BirthdayCandidate) -> BirthdayDuplicateStatus,
         onImport: @escaping ([BirthdayCandidate], Int, String, Bool, String, String) throws -> Void) {
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

    private var importable: [BirthdayCandidate] {
        visible.filter { status($0) != .imported && selected.contains($0.id) }
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
        !categoryName.isEmpty && !importable.isEmpty && destination != nil
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
                                    Text(candidate.eventTitle).foregroundStyle(.primary)
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
                    if !cameFromGroup {
                        Button {
                            request = UUID()
                        } label: {
                            Label("再選聯絡人", systemImage: "person.badge.plus")
                        }
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
                    importModePicker
                    birthdayCalendarFields
                    if mode == .draft {
                        Text("會保存目的行事曆，但現在只建立草稿，不寫入事件。")
                            .font(.footnote).foregroundStyle(.secondary)
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
            ) { explicitlySelectedCalendarID = $0 }
        }
        if let calendarError, calendar.destinations.isEmpty {
            Text(calendarError).font(.footnote).foregroundStyle(.red)
        }
        if !calendar.destinations.contains(where: \.isWritable) {
            Text("匯入前請先連接或選擇一個可寫入的行事曆。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var importModePicker: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 3))
            : AnyLayout(HStackLayout(spacing: 3))
        return layout {
            ForEach(ImportMode.allCases, id: \.self) { option in
                importModeButton(option)
            }
        }
        .padding(3)
        .background(Color(uiColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("birthday-import-mode")
    }

    private func importModeButton(_ option: ImportMode) -> some View {
        let isSelected = mode == option
        let shape = RoundedRectangle(cornerRadius: 9)
        return Button {
            mode = option
        } label: {
            Text(option.rawValue)
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
                                if option == .draft {
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
    }

    private func performImport() {
        guard canImport, let destination else { return }
        errorMessage = nil
        do {
            try onImport(importable, years, destination.id, mode == .apply, categoryName, subcategoryName)
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
    let onImport: ([BirthdayCandidate], Int, String, Bool, String, String) throws -> Void

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
                            Text("讀取群組需要完整通訊錄存取。CalStitch 只會讀取所選群組成員的姓名和生日；若不想開放完整存取，可回上一頁使用個別選人。")
                            Button("讀取聯絡人群組") { loadGroups(allowPrompt: true) }
                        case .loading:
                            ProgressView("讀取中…")
                        case .settings:
                            Text("群組匯入需要通訊錄的「完整取用權限」，請到「設定」變更權限。")
                            Button("開啟設定", action: openSettings)
                            if settingsOpenFailed {
                                Text("無法開啟設定，請手動到設定變更權限。")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        case .restricted:
                            Text("這台裝置限制了通訊錄存取，無法讀取群組。請回上一頁使用個別選人。")
                        case .groups(let groups):
                            if groups.isEmpty {
                                Text("找不到通訊錄群組。可改用個別選人。")
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
                            Text("無法讀取通訊錄群組或成員。請檢查權限後重試。")
                            Button("重試") { loadGroups() }
                        }
                        Section {
                            Button("改用個別選人") {
                                BirthdayGroupSettingsReturn.clear()
                                task?.cancel()
                                onChoosePeople()
                            }
                        }
                    }
                    .navigationTitle("從群組匯入生日")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") {
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
            return GroupOption(id: group.id, name: group.name, detail: "\(group.detail ?? "同名群組") · \(index + 1)")
        }
    }

    nonisolated private static func readMembers(of group: GroupOption) throws -> BirthdayPickerSelection {
        let store = CNContactStore()
        let keys: [any CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactGivenNameKey as NSString, CNContactFamilyNameKey as NSString,
            CNContactOrganizationNameKey as NSString,
            CNContactBirthdayKey as NSString, CNContactNonGregorianBirthdayKey as NSString
        ]
        let predicate = CNContact.predicateForContactsInGroup(withIdentifier: group.id)
        return BirthdayPickerSelection(try store.unifiedContacts(matching: predicate, keysToFetch: keys),
                                       groupName: group.name)
    }
}
