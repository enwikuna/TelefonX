import AppKit

/// Inset the native table while preserving selection overhang around row content.
class InsetListScrollView: NSScrollView {
    override func tile() {
        super.tile()
        var frame = contentView.frame
        let inset = min(HistoryRowLayout.nativeTableHorizontalInset, frame.width / 2)
        frame.origin.x += inset
        frame.size.width -= inset * 2
        contentView.frame = frame
    }
}
