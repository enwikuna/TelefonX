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
        let mask = try #require(scroll.layer?.mask)
        let gradient = try #require(mask as? CAGradientLayer)
        let colors = try #require(gradient.colors as? [CGColor])
        #expect(scroll.contentView.layer?.mask == nil)
        #expect(mask.frame == scroll.layer?.bounds)
        #expect(colors.map(\.alpha) == [1, 1, 0.42, 0.14, 0.03, 0, 0])
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 320))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(scroll.layer?.mask === mask)
        #expect(mask.frame == scroll.layer?.bounds)
        scroll.fadeHeight = nil
        #expect(scroll.layer?.mask == nil)
        #expect(scroll.contentView.bounds.minY == 320)
    }
}

private final class Document: NSView {
    override var isFlipped: Bool { true }
}
