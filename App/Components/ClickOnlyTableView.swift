import AppKit

/// Select on click while leaving horizontal swipe gestures to AppKit.
final class ClickOnlyTableView: NSTableView {
    private static let dragThreshold: CGFloat = 3
    private var selectionAnchor: Int?
    var selectAllInContext: ((Int) -> Void)?

    override func selectAll(_ sender: Any?) {
        guard let selectAllInContext else {
            super.selectAll(sender)
            return
        }
        let reference = selectionAnchor.flatMap { selectedRowIndexes.contains($0) ? $0 : nil } ?? selectedRow
        selectAllInContext(reference)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown, let window else {
            super.mouseDown(with: event)
            return
        }

        let origin = event.locationInWindow
        var dragged = false
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let distance = hypot(next.locationInWindow.x - origin.x, next.locationInWindow.y - origin.y)
            if distance >= Self.dragThreshold { dragged = true }
        }

        guard !dragged else { return }

        window.makeFirstResponder(self)
        let clicked = row(at: convert(origin, from: nil))
        if clicked >= 0 {
            if allowsMultipleSelection, event.modifierFlags.contains(.shift),
               let anchor = selectionAnchor ?? selectedRowIndexes.first {
                selectRowIndexes(IndexSet(integersIn: min(anchor, clicked)..<(max(anchor, clicked) + 1)),
                                 byExtendingSelection: event.modifierFlags.contains(.command))
            } else if allowsMultipleSelection, event.modifierFlags.contains(.command) {
                if selectedRowIndexes.contains(clicked) {
                    deselectRow(clicked)
                    if selectionAnchor == clicked { selectionAnchor = selectedRowIndexes.last }
                } else {
                    selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: true)
                    selectionAnchor = clicked
                }
            } else {
                selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
                selectionAnchor = clicked
            }
        } else if allowsEmptySelection {
            deselectAll(nil)
            selectionAnchor = nil
        }

        if event.clickCount >= 2, clicked >= 0, selectedRowIndexes.contains(clicked), let doubleAction {
            NSApp.sendAction(doubleAction, to: target, from: self)
        }
    }
}
