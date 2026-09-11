import Testing
@testable import TelefonX

@Suite struct FavoritesStripLayoutTests {
    @Test func reservesShowAllOnlyWhenNeeded() {
        #expect(FavoritesStripLayout.visibleCount(total: 6, width: 496) == 6)
        #expect(FavoritesStripLayout.visibleCount(total: 7, width: 496) == 5)
        #expect(FavoritesStripLayout.visibleCount(total: 27, width: 1000) == 11)
        #expect(FavoritesStripLayout.visibleCount(total: 0, width: 0) == 0)
    }

    @Test func smallFavoriteSetsAlsoFillTheStrip() {
        #expect(FavoritesStripLayout.tileWidth(total: 0, width: 500) == 0)
        #expect(FavoritesStripLayout.tileWidth(total: 1, width: 500) == 500)
        #expect(FavoritesStripLayout.tileWidth(total: 2, width: 500) == 246)
    }

    @Test func resizingNeverOverflowsAvailableWidth() {
        for width in stride(from: 84, through: 2000, by: 7) {
            let visible = FavoritesStripLayout.visibleCount(total: 27, width: Double(width))
            let tiles = visible + (visible < 27 ? 1 : 0)
            let tileWidth = FavoritesStripLayout.tileWidth(total: 27, width: Double(width))
            #expect(tileWidth >= 76)
            #expect(abs(tileWidth * Double(tiles) + Double(max(0, tiles - 1) * 8) - Double(width)) < 0.001)
        }
    }
}
