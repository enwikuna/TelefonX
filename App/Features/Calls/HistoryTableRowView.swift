import AppKit

final class HistoryTableRowView: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
    // Selection and separator travel with the hosted content during native swipes.
    override func drawSelection(in dirtyRect: NSRect) {}
}
