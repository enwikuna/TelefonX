import Observation
import ServiceManagement

enum LoginItemStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable
}

@MainActor protocol LoginItemServicing {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() async throws
    func openSystemSettings()
}

@MainActor struct SystemLoginItemService: LoginItemServicing {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    func register() throws { try SMAppService.mainApp.register() }
    func unregister() async throws { try await SMAppService.mainApp.unregister() }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

@MainActor @Observable final class LoginItemManager {
    private let service: any LoginItemServicing
    private(set) var status: LoginItemStatus
    private(set) var busy = false
    var errorMessage: String?

    init(service: any LoginItemServicing = SystemLoginItemService()) {
        self.service = service
        status = service.status
    }

    var isRegistered: Bool { status == .enabled || status == .requiresApproval }

    func refresh() { status = service.status }

    func setRegistered(_ registered: Bool) async {
        guard registered != isRegistered, !busy else { return }
        busy = true
        defer {
            status = service.status
            busy = false
        }
        do {
            if registered { try service.register() }
            else { try await service.unregister() }
        } catch {
            errorMessage = L10n.error(error)
        }
    }

    func openSystemSettings() { service.openSystemSettings() }
}
