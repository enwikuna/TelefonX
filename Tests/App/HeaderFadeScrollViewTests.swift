import AppKit
import Testing
@testable import TelefonX

@Suite @MainActor struct HeaderFadeScrollViewTests {
    @Test func fadeTracksViewportAndIsRemovedWithoutHeader() throws {
        let scroll = HeaderFadeScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 600))
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = Document(frame: NSRect(x: 0, y: 0, width: 500, height: 2000))
        scroll.contentInsets.top = 180
        scroll.fadeHeight = 40
        scroll.tile()
        #expect(scroll.contentView.layer?.mask != nil)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 320))
        scroll.reflectScrolledClipView(scroll.contentView)
        let mask = try #require(scroll.contentView.layer?.mask)
        #expect(mask.frame == scroll.contentView.bounds)
        scroll.fadeHeight = nil
        #expect(scroll.contentView.layer?.mask == nil)
        #expect(scroll.contentView.bounds.minY == 320)
    }
}

private final class Document: NSView {
    override var isFlipped: Bool { true }
}
