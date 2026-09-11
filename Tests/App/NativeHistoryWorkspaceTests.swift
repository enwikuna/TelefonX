import AppKit
import SwiftUI
import Testing
@testable import TelefonX

@Suite @MainActor struct NativeHistoryWorkspaceTests {
    @Test func headerCanAppearUpdateDisappearAndReturnWithoutDuplicates() throws {
        _ = NSApplication.shared
        let controller = NativeHistoryWorkspace.Controller(scroll: NSScrollView())
        let item = try #require(controller.splitViewItems.first)
        let header = AnyView(Color.clear.frame(height: 140))
        controller.setHeader(header)
        let accessory = try #require(item.topAlignedAccessoryViewControllers.first)
        controller.setHeader(header)
        #expect(item.topAlignedAccessoryViewControllers.count == 1)
        #expect(item.topAlignedAccessoryViewControllers.first === accessory)
        controller.setHeader(nil)
        #expect(item.topAlignedAccessoryViewControllers.isEmpty)
        controller.setHeader(header)
        #expect(item.topAlignedAccessoryViewControllers.count == 1)
        #expect(controller.scroll.automaticallyAdjustsContentInsets)
    }
}
