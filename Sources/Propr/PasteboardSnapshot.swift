import AppKit

/// A copy of the pasteboard's contents that can be put back later.
///
/// Holds the *data* of each item, not the `NSPasteboardItem` objects themselves.
/// Writing the original items back after `clearContents()` raises
/// `NSInvalidArgumentException: Cannot write pasteboard item … It is already
/// associated with another pasteboard` — every time, whether or not anything was
/// copied in between.
///
/// That exception was the root of Propr's recurring crash. It was raised inside a
/// Swift task running on the main thread; AppKit caught it and carried on, but the
/// unwind skipped the concurrency runtime's own cleanup, leaving its record of the
/// current executor pointing into a dead stack frame. The next main-actor isolation
/// check anywhere in the app — the hotkey monitor, the menu-bar menu — then read
/// garbage and crashed. It also left the user's clipboard empty, because the clear
/// succeeded and the write did not.
struct PasteboardSnapshot {
    /// One entry per pasteboard item, mapping each type it offered to its data.
    private let items: [[NSPasteboard.PasteboardType: Data]]

    /// Reads every representation eagerly. Data promised lazily by the app that
    /// owns the pasteboard has to be fetched now: once another app copies, the
    /// original owner is no longer asked for it.
    init(of pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var representations: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    representations[type] = data
                }
            }
            return representations
        }
    }

    var isEmpty: Bool { items.isEmpty }

    /// Replaces the pasteboard's contents with this snapshot, using newly created
    /// items so the write can never be rejected as a reused item.
    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        let fresh: [NSPasteboardItem] = items.compactMap { representations in
            guard !representations.isEmpty else { return nil }
            let item = NSPasteboardItem()
            for (type, data) in representations {
                item.setData(data, forType: type)
            }
            return item
        }

        if !fresh.isEmpty {
            pasteboard.writeObjects(fresh)
        }
    }
}
