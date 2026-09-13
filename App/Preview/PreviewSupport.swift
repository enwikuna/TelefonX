import Foundation
import SwiftUI
import TelefonDomain

enum PreviewSupport {
    static var enabled: Bool {
        #if DEBUG
        Bundle.main.bundleIdentifier == "de.enwikuna.TelefonX.preview"
        #else
        false
        #endif
    }

    @MainActor static func makeModel() -> PhoneModel {
        #if DEBUG
        if enabled {
            return PreviewFixtures.makeModel(dialTones: DialTonePlayer(),
                                             pro: !CommandLine.arguments.contains("--free-preview"))
        }
        #endif
        return LivePhoneModelFactory.makeModel()
    }
}

#if DEBUG
enum PreviewScenario: String, CaseIterable, Identifiable {
    case idle = "Dial", noLines = "No Line", connected = "Call", incoming = "Incoming", multiple = "Two Calls"
    case fiveCalls = "Five Calls"
    case singleRecord = "One Call", multipleLines = "Multiple Lines", empty = "Empty Recents"
    case avatars = "Contact Photos", favorites = "Favorites", reminders = "Call Reminders"
    case remindersNoLines = "Call Reminders Without a Line"
    case emptyHistoryWithLine = "Empty Recents With a Line", emptyHistoryNoLine = "Empty Recents Without a Line"
    case emptyRemindersWithLine = "Empty Callbacks With a Line", emptyRemindersNoLine = "Empty Callbacks Without a Line"
    case emptyFavoritesWithLine = "Empty Favorites With a Line", emptyFavoritesNoLine = "Empty Favorites Without a Line"
    case emptyContactsWithLine = "Empty Contacts With a Line", emptyContactsNoLine = "Empty Contacts Without a Line"
    var isEmptyList: Bool {
        switch self {
        case .emptyHistoryWithLine, .emptyHistoryNoLine, .emptyRemindersWithLine, .emptyRemindersNoLine,
             .emptyFavoritesWithLine, .emptyFavoritesNoLine, .emptyContactsWithLine, .emptyContactsNoLine: true
        default: false
        }
    }
    var omitsLine: Bool {
        switch self {
        case .emptyHistoryNoLine, .emptyRemindersNoLine, .emptyFavoritesNoLine, .emptyContactsNoLine: true
        default: false
        }
    }
    var id: Self { self }
    var title: String { L10n.text(rawValue) }
    var initialSection: PhoneSection {
        switch self {
        case .avatars, .emptyContactsWithLine, .emptyContactsNoLine: .contacts
        case .favorites, .emptyFavoritesWithLine, .emptyFavoritesNoLine: .favorites
        case .reminders, .remindersNoLines, .emptyRemindersWithLine, .emptyRemindersNoLine: .reminders
        default: .history
        }
    }
}

/// Shared only by the preview's main window and its separate controls window.
@MainActor @Observable final class PreviewPresentation {
    var scenario: PreviewScenario = .connected
    var appearance = "System"
    var colorScheme: ColorScheme? {
        appearance == "System" ? nil : (appearance == "Light" ? .light : .dark)
    }
}

struct PreviewHarness: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let presentation: PreviewPresentation

    var body: some View {
        // Preserve the window's native toolbar/scroll-view association across scenarios.
        MainView(initialSection: presentation.scenario.initialSection)
            .onChange(of: presentation.scenario) { _, value in PreviewFixtures.apply(value, to: model) }
            .preferredColorScheme(presentation.colorScheme)
            .task(id: presentation.scenario) {
                await model.setAppleContactsEnabled(!presentation.scenario.isEmptyList)
            }
            .task { openWindow(id: "preview-controls") }
    }
}

struct PreviewControls: View {
    @Environment(PhoneModel.self) private var model
    @Bindable var presentation: PreviewPresentation
    @State private var audioSettings = false
    @State private var accountEditor: PhoneAccount?

    var body: some View {
        Form {
            Picker("View", selection: $presentation.scenario) {
                ForEach(PreviewScenario.allCases) { Text($0.title).tag($0) }
            }
            Picker("Colors", selection: $presentation.appearance) {
                ForEach(["System", "Light", "Dark"], id: \.self) { Text(L10n.text($0)).tag($0) }
            }
            HStack {
                Button("Line …") { accountEditor = model.snapshot.accounts.first }
                    .disabled(model.snapshot.accounts.isEmpty)
                Button("Audio …") { audioSettings = true }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $audioSettings) {
            VStack {
                AudioSettings()
                Button("Close") { audioSettings = false }.keyboardShortcut(.cancelAction).padding()
            }.frame(width: 680, height: 620).telefonButtonStyle()
        }
        .sheet(item: $accountEditor) { AccountEditor(account: $0) }
    }
}

@MainActor enum PreviewFixtures {
    private static var usesGermanLocalization: Bool {
        Bundle.main.preferredLocalizations.first == "de"
    }

    private static func localized(_ german: String, _ english: String) -> String {
        usesGermanLocalization ? german : english
    }

    static func makeModel(muteFeedback: any MuteFeedbackPlaying = PreviewMuteFeedback(),
                          dialTones: (any DialTonePlaying)? = nil, pro: Bool = true) -> PhoneModel {
        let engine = PreviewEngine()
        let appleContacts = [
            AppleContact(id: "preview-apple-lena", name: "Lena Beispiel",
                         company: localized("Beispiel Studio", "Example Studio"),
                         phoneNumbers: [ContactPhoneNumber(value: "106", label: .work)], photoData: nil),
            AppleContact(id: "preview-apple-noah", name: "Noah Muster", company: "",
                         phoneNumbers: [ContactPhoneNumber(value: "107", label: .mobile)], photoData: nil)
        ]
        let model = PhoneModel(engine: engine, credentials: PreviewCredentials(), repository: PreviewRepository(),
                               dialTones: dialTones ?? PreviewTones(), muteFeedback: muteFeedback,
                               authorizeMicrophone: { true },
                               appleContactsProvider: PreviewAppleContactsProvider(contacts: appleContacts),
                               initialAppleContactsEnabled: true, initialAppleContacts: appleContacts,
                               purchases: PurchaseStore(internalEvaluation: pro, productIDs: []))
        engine.model = model
        model.ready = true
        apply(.connected, to: model)
        return model
    }

    static func apply(_ scenario: PreviewScenario, to model: PhoneModel) {
        if scenario.isEmptyList {
            apply(.idle, to: model)
            model.snapshot.contacts = []
            model.snapshot.history = []
            model.snapshot.reminders = []
            if scenario.omitsLine {
                model.snapshot.accounts = []
                model.selectedAccountID = nil
                model.registrations = [:]
            }
            return
        }
        if scenario == .remindersNoLines {
            apply(.reminders, to: model)
            model.snapshot.accounts = []
            model.selectedAccountID = nil
            model.registrations = [:]
            for index in model.snapshot.reminders.indices {
                model.snapshot.reminders[index].accountID = nil
            }
            return
        }
        model.snapshot = AppSnapshot()
        model.selectedAccountID = nil
        model.registrations = [:]
        model.calls = []
        model.finished = []
        model.conferenceHandles = []
        model.dialText = ""
        model.suppressCallerIDOnce = false
        model.errorMessage = nil
        model.information = nil
        model.lastEndedCall = nil
        guard scenario != .noLines else { return }

        var account = PhoneAccount()
        account.name = "Home"; account.domain = "sip.example.com"; account.username = "preview"
        model.snapshot.accounts = [account]; model.selectedAccountID = account.id
        model.registrations = [account.id: .registered]
        if scenario == .multipleLines {
            for name in [localized("Büro", "Office"), localized("Standort Süd", "South Office")] {
                var additional = PhoneAccount()
                additional.name = name; additional.domain = "sip.example.com"; additional.username = "preview"
                model.snapshot.accounts.append(additional)
                model.registrations[additional.id] = .registered
            }
        }
        model.snapshot.contacts = [
            PhoneContact(name: "Alex Beispiel", numbers: ["101"], group: localized("Vertrieb", "Sales")),
            PhoneContact(name: "Sam Muster", numbers: ["102"], group: "Support")
        ]
        if scenario == .fiveCalls {
            model.snapshot.contacts += [PhoneContact(name: "Chris Demo", numbers: ["103"]),
                                        PhoneContact(name: "Robin Test", numbers: ["104"]),
                                        PhoneContact(name: "Kim Beispiel", numbers: ["105"])]
        }
        let now = Date()
        let call = session(account: account.id, slot: 0, remote: "101", start: now.addingTimeInterval(-125))
        var incoming = session(account: account.id, slot: 1, remote: "102", start: now, incoming: true)
        incoming.answeredAt = nil; incoming.phase = .incoming
        switch scenario {
        case .connected: model.calls = [call]
        case .incoming: model.calls = [incoming]
        case .multiple:
            var held = call; held.held = true
            model.calls = [held, session(account: account.id, slot: 1, remote: "102", start: now.addingTimeInterval(-30))]
        case .fiveCalls:
            model.calls = (0..<5).map { index in
                var previewCall = session(account: account.id, slot: Int32(index), remote: "\(101 + index)",
                                          start: now.addingTimeInterval(-Double((5 - index) * 30)))
                previewCall.held = index < 4
                return previewCall
            }
        case .idle, .singleRecord, .multipleLines, .empty, .avatars, .favorites, .reminders: model.calls = []
        case .noLines, .remindersNoLines,
             .emptyHistoryWithLine, .emptyHistoryNoLine, .emptyRemindersWithLine, .emptyRemindersNoLine,
             .emptyFavoritesWithLine, .emptyFavoritesNoLine, .emptyContactsWithLine, .emptyContactsNoLine: break
        }
        if scenario != .empty {
            let count = scenario == .singleRecord ? 1 : (scenario == .favorites ? 32 : 8)
            let dayOffsets = [0, 0, 1, 2, 3, 6, 7, 8]
            model.snapshot.history = (0..<count).map { index in
                let start = Calendar.current.date(byAdding: .day, value: -dayOffsets[index % dayOffsets.count], to: now)!
                    .addingTimeInterval(-Double(index == 1 ? 1200 : 600))
                var prior = session(account: account.id, slot: Int32(index + 3), remote: index % 2 == 0 ? "101" : "102",
                                    start: start, incoming: index % 3 != 0)
                prior.endedAt = prior.startedAt.addingTimeInterval(180)
                if index == 2 || index == 5 { prior.answeredAt = nil }
                return CallRecord(session: prior, accountName: account.name)
            }
        }
        if scenario == .avatars || scenario == .favorites {
            let northOffice = localized("Nord Büro", "North Office")
            model.snapshot.contacts += [PhoneContact(name: northOffice, company: northOffice, numbers: ["103"]),
                                        PhoneContact(name: localized("Foto-Test", "Photo Test"), numbers: ["104"],
                                                     photoData: PreviewContactPhoto.make())]
            model.snapshot.blocks = [BlockRule(number: "102")]
            model.snapshot.contacts[0].favorite = true
            for index in model.snapshot.history.indices {
                model.snapshot.history[index].remote = ["101", "102", "103", "104", "105", "anonymous", "101", "104"][index % 8]
            }
        }
        if scenario == .favorites {
            model.snapshot.contacts[0].numbers.append("201")
            model.snapshot.contacts += [PhoneContact(name: "Chris Demo", numbers: ["106"]),
                                       PhoneContact(name: "Robin Test", numbers: ["107"]),
                                       PhoneContact(name: "Kim Beispiel", numbers: ["108"])]
            // Enough rows to exercise real scrolling in both Favorites and Contacts.
            model.snapshot.contacts += (1...20).map {
                PhoneContact(name: "Scroll-Test \($0)", numbers: ["\(200 + $0)"])
            }
            for index in model.snapshot.contacts.indices {
                model.snapshot.contacts[index].favorite = true
                model.snapshot.contacts[index].favoriteOrder = index
                model.snapshot.contacts[index].favoriteNumber = model.snapshot.contacts[index].numbers.first
            }
        }
        if scenario == .reminders {
            let calendar = Calendar.current
            let startOfTomorrow = calendar.date(byAdding: .day, value: 1,
                                                 to: calendar.startOfDay(for: now))!
            let remainingToday = startOfTomorrow.timeIntervalSince(now)
            model.snapshot.reminders = [
                CallReminder(name: "Alex Beispiel", number: "101",
                             note: localized("Angebot besprechen", "Discuss quote"),
                             dueAt: now.addingTimeInterval(-20 * 60), accountID: account.id,
                             contactID: model.snapshot.contacts[0].id),
                CallReminder(name: "Petra Hoffmann", number: "105",
                             note: localized("Freigabe abstimmen", "Coordinate approval"),
                             dueAt: now.addingTimeInterval(-5 * 60), accountID: account.id),
                CallReminder(name: "Jonas Wagner", number: "109",
                             note: localized("Vertragsdetails klären", "Clarify contract details"),
                             dueAt: now.addingTimeInterval(-45 * 60), accountID: account.id),
                CallReminder(name: "Carla Neumann", number: "110",
                             note: localized("Rückruf erbeten", "Callback requested"),
                             dueAt: now.addingTimeInterval(-75 * 60), accountID: account.id),
                CallReminder(name: "Sam Muster", number: "102",
                             note: localized("Nach Liefertermin fragen", "Ask about the delivery date"),
                             dueAt: now.addingTimeInterval(remainingToday * 0.2), accountID: account.id,
                             contactID: model.snapshot.contacts[1].id),
                CallReminder(name: "Mia Beispiel", number: "106",
                             note: localized("Rückmeldung zum Angebot", "Follow up on the quote"),
                             dueAt: now.addingTimeInterval(remainingToday * 0.4), accountID: account.id),
                CallReminder(name: "Paul Richter", number: "111",
                             note: localized("Projektstatus besprechen", "Discuss project status"),
                             dueAt: now.addingTimeInterval(remainingToday * 0.6), accountID: account.id),
                CallReminder(name: "Eva Sommer", number: "112",
                             note: localized("Termin neu abstimmen", "Reschedule appointment"),
                             dueAt: now.addingTimeInterval(remainingToday * 0.8), accountID: account.id),
                CallReminder(name: localized("Nord Büro", "North Office"), number: "103", note: "",
                             dueAt: calendar.date(byAdding: .day, value: 2, to: now)!, accountID: account.id),
                CallReminder(name: localized("Süd Büro", "South Office"), number: "107",
                             note: localized("Termin bestätigen", "Confirm appointment"),
                             dueAt: calendar.date(byAdding: .day, value: 3, to: now)!, accountID: account.id),
                CallReminder(name: localized("West Büro", "West Office"), number: "113",
                             note: localized("Unterlagen nachreichen", "Send remaining documents"),
                             dueAt: calendar.date(byAdding: .day, value: 4, to: now)!, accountID: account.id),
                CallReminder(name: localized("Ost Büro", "East Office"), number: "114",
                             note: localized("Budget abstimmen", "Discuss budget"),
                             dueAt: calendar.date(byAdding: .day, value: 5, to: now)!, accountID: account.id),
                CallReminder(name: "Chris Demo", number: "104",
                             note: localized("Unterlagen sind angekommen", "Documents received"),
                             dueAt: now.addingTimeInterval(-86_400), completedAt: now.addingTimeInterval(-3600),
                             accountID: account.id),
                CallReminder(name: "Lena Beispiel", number: "108",
                             note: localized("Angebot versendet", "Quote sent"),
                             dueAt: now.addingTimeInterval(-172_800), completedAt: now.addingTimeInterval(-7200),
                             accountID: account.id),
                CallReminder(name: "Robert Klein", number: "115",
                             note: localized("Rückfrage erledigt", "Question resolved"),
                             dueAt: now.addingTimeInterval(-259_200), completedAt: now.addingTimeInterval(-10_800),
                             accountID: account.id),
                CallReminder(name: "Anna Fischer", number: "116",
                             note: localized("Termin bestätigt", "Appointment confirmed"),
                             dueAt: now.addingTimeInterval(-345_600), completedAt: now.addingTimeInterval(-14_400),
                             accountID: account.id)
            ]
        }
    }

    static func session(account: UUID, slot: Int32, remote: String, start: Date, incoming: Bool = false) -> CallSession {
        var call = CallSession(handle: CallHandle(slot: slot, generation: UInt64.random(in: 1...UInt64.max)),
                               accountID: account, remote: remote, incoming: incoming, phase: .connected, startedAt: start)
        call.answeredAt = start
        call.quality = CallQuality(codec: "Opus", clockRate: 48000, receivedPackets: 2500, lostPackets: 0,
                                   jitterMilliseconds: 2, roundTripMilliseconds: 20, secureMedia: true)
        return call
    }
}

private struct PreviewAppleContactsProvider: AppleContactsProviding {
    let contacts: [AppleContact]
    func authorizationStatus() -> AppleContactsAuthorization { .authorized }
    func requestAccess() async throws -> Bool { true }
    func fetch() async throws -> [AppleContact] { contacts }
}

/// In-memory only; no native engine is instantiated and the preview bundle has no network/microphone entitlements.
@MainActor private final class PreviewEngine: TelephonyService {
    nonisolated let events = AsyncStream<TelephonyEvent> { $0.finish() }
    weak var model: PhoneModel?
    func start() async {}
    func stop() async {}
    func register(_ account: PhoneAccount, password: String) async {}
    func unregister(_ id: UUID) async {}
    func verifyRegistration(_ id: UUID) async -> Bool { true }
    func call(_ destination: CallDestination, account: PhoneAccount) async throws -> CallHandle {
        let call = PreviewFixtures.session(account: account.id, slot: 9, remote: destination.value, start: Date())
        model?.calls.append(call)
        return call.handle
    }
    func answer(_ call: CallHandle) async throws { update(call) { $0.transition(to: .connected) } }
    func hangup(_ call: CallHandle, decline: Bool) async throws { model?.calls.removeAll { $0.handle == call } }
    func mute(_ call: CallHandle, muted: Bool) async throws {}
    func hold(_ call: CallHandle, held: Bool) async throws { update(call) { $0.held = held } }
    func setHoldMusic(_ file: URL?) async throws {}
    func sendDTMF(_ digit: String, call: CallHandle) async throws {}
    func conference(_ first: CallHandle, with second: CallHandle, enabled: Bool) async throws {}
    func transfer(_ source: CallHandle, to consultation: CallHandle) async throws { model?.calls.removeAll { $0.handle == source || $0.handle == consultation } }
    func quality(_ call: CallHandle) async throws -> CallQuality { throw EngineError(-1, operation: "Preview") }
    func audioDevices() async -> [AudioDevice] { [] }
    func setAudio(input: Int32, output: Int32) async throws {}
    func releaseAudio() async {}
    func networkChanged() async throws {}
    private func update(_ handle: CallHandle, change: (inout CallSession) -> Void) {
        guard let model, let index = model.calls.firstIndex(where: { $0.handle == handle }) else { return }
        change(&model.calls[index])
    }
}

@MainActor private final class PreviewRepository: PhoneRepository {
    func load() -> AppSnapshot { AppSnapshot() }
    func save(_ snapshot: AppSnapshot, changes: SnapshotChanges) {}
}
private struct PreviewCredentials: CredentialStore {
    func password(for id: UUID) -> String? { nil }
    func setPassword(_ password: String, for id: UUID) {}
    func deletePassword(for id: UUID) {}
}
@MainActor private struct PreviewTones: DialTonePlaying {
    func play(_ digit: Character, outputUID: String) {}
    func playCallFailure(outputUID: String) {}
    func stop() {}
}
@MainActor struct PreviewMuteFeedback: MuteFeedbackPlaying {
    func play(muted: Bool, outputUID: String) {}
}
#endif
