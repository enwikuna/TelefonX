struct ListSearchState: Equatable {
    var text = ""
    private(set) var focusRequest = 0

    mutating func focus() {
        focusRequest += 1
    }

    mutating func clear() { text = "" }
}

/// Window-local search state for each primary list. Switching sections must
/// not leak a query into another list, while returning to a section should
/// restore the query for the lifetime of the window.
struct SectionSearchStates: Equatable {
    private var history = ListSearchState()
    private var reminders = ListSearchState()
    private var favorites = ListSearchState()
    private var contacts = ListSearchState()

    subscript(section: PhoneSection) -> ListSearchState {
        get {
            switch section {
            case .history: history
            case .reminders: reminders
            case .favorites: favorites
            case .contacts: contacts
            }
        }
        set {
            switch section {
            case .history: history = newValue
            case .reminders: reminders = newValue
            case .favorites: favorites = newValue
            case .contacts: contacts = newValue
            }
        }
    }
}
