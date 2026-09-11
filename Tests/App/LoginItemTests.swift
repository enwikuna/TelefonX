import Foundation
import Testing
@testable import TelefonX

@Suite @MainActor struct LoginItemTests {
    @Test func registrationAndRemovalFollowSystemStatus() async {
        let service = TestLoginItemService()
        let manager = LoginItemManager(service: service)
        #expect(!manager.isRegistered)

        await manager.setRegistered(true)
        #expect(manager.status == .enabled)
        #expect(manager.isRegistered)
        #expect(service.registerCount == 1)

        await manager.setRegistered(false)
        #expect(manager.status == .notRegistered)
        #expect(!manager.isRegistered)
        #expect(service.unregisterCount == 1)
    }

    @Test func approvalStatusRemainsSelectedAndOpensSystemSettings() async {
        let service = TestLoginItemService(statusAfterRegistration: .requiresApproval)
        let manager = LoginItemManager(service: service)

        await manager.setRegistered(true)
        #expect(manager.status == .requiresApproval)
        #expect(manager.isRegistered)
        manager.openSystemSettings()
        #expect(service.openSettingsCount == 1)
    }

    @Test func registrationFailureRestoresActualStateAndReportsError() async {
        let service = TestLoginItemService(registerError: TestLoginItemError.denied)
        let manager = LoginItemManager(service: service)

        await manager.setRegistered(true)
        #expect(manager.status == .notRegistered)
        #expect(!manager.isRegistered)
        #expect(manager.errorMessage == TestLoginItemError.denied.localizedDescription)
        #expect(!manager.busy)
    }
}

private enum TestLoginItemError: LocalizedError {
    case denied
    var errorDescription: String? { "Not Allowed" }
}

@MainActor private final class TestLoginItemService: LoginItemServicing {
    var status: LoginItemStatus = .notRegistered
    let statusAfterRegistration: LoginItemStatus
    let registerError: Error?
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openSettingsCount = 0

    init(statusAfterRegistration: LoginItemStatus = .enabled, registerError: Error? = nil) {
        self.statusAfterRegistration = statusAfterRegistration
        self.registerError = registerError
    }

    func register() throws {
        registerCount += 1
        if let registerError { throw registerError }
        status = statusAfterRegistration
    }

    func unregister() async throws {
        unregisterCount += 1
        status = .notRegistered
    }

    func openSystemSettings() { openSettingsCount += 1 }
}
