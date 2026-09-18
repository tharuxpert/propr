import AppKit
import Testing

@testable import Propr

/// The clipboard round trip used when Propr has to borrow ⌘C in another app.
///
/// Every test uses a private named pasteboard, never the user's real clipboard.
@MainActor
@Suite(.serialized)
struct PasteboardSnapshotTests {

    private func makePasteboard(_ suffix: String = #function) -> NSPasteboard {
        let pb = NSPasteboard(name: NSPasteboard.Name("com.tharuxpert.propr.tests.\(suffix)"))
        pb.clearContents()
        return pb
    }

    /// The exact sequence that used to raise NSInvalidArgumentException ("already
    /// associated with another pasteboard") and strand the concurrency runtime's
    /// executor record. An uncaught exception here would take down the test run, so
    /// reaching the expectations at all is the point of this test.
    @Test("Restoring after another copy puts the original back without raising")
    func restoreAfterAnotherCopy() {
        let pb = makePasteboard()
        pb.setString("what the user had copied", forType: .string)

        let snapshot = PasteboardSnapshot(of: pb)

        // The source app answers ⌘C.
        pb.clearContents()
        pb.setString("copied from the source app", forType: .string)

        snapshot.restore(to: pb)

        #expect(pb.string(forType: .string) == "what the user had copied")
        pb.releaseGlobally()
    }

    /// The other half of the old bug: nothing was copied in between, yet writing the
    /// original items back still raised — and the clipboard was left empty.
    @Test("Restoring when nothing was copied leaves the clipboard intact")
    func restoreWhenNothingCopied() {
        let pb = makePasteboard()
        pb.setString("what the user had copied", forType: .string)

        PasteboardSnapshot(of: pb).restore(to: pb)

        #expect(pb.string(forType: .string) == "what the user had copied")
        pb.releaseGlobally()
    }

    @Test("Every representation of an item survives, not just plain text")
    func multipleRepresentations() {
        let pb = makePasteboard()
        let custom = NSPasteboard.PasteboardType("com.tharuxpert.propr.tests.custom")
        let item = NSPasteboardItem()
        item.setString("plain", forType: .string)
        item.setData(Data([0x01, 0x02, 0x03]), forType: custom)
        pb.writeObjects([item])

        let snapshot = PasteboardSnapshot(of: pb)
        pb.clearContents()
        pb.setString("overwritten", forType: .string)
        snapshot.restore(to: pb)

        #expect(pb.string(forType: .string) == "plain")
        #expect(pb.data(forType: custom) == Data([0x01, 0x02, 0x03]))
        pb.releaseGlobally()
    }

    @Test("Multiple items are restored as separate items")
    func multipleItems() {
        let pb = makePasteboard()
        let first = NSPasteboardItem()
        first.setString("one", forType: .string)
        let second = NSPasteboardItem()
        second.setString("two", forType: .string)
        pb.writeObjects([first, second])

        let snapshot = PasteboardSnapshot(of: pb)
        pb.clearContents()
        snapshot.restore(to: pb)

        #expect(pb.pasteboardItems?.compactMap { $0.string(forType: .string) } == ["one", "two"])
        pb.releaseGlobally()
    }

    @Test("An empty clipboard is restored as empty")
    func emptyClipboard() {
        let pb = makePasteboard()

        let snapshot = PasteboardSnapshot(of: pb)
        #expect(snapshot.isEmpty)

        pb.setString("copied from the source app", forType: .string)
        snapshot.restore(to: pb)

        #expect(pb.pasteboardItems?.isEmpty ?? true)
        pb.releaseGlobally()
    }

    @Test("A snapshot can be restored more than once")
    func restoreTwice() {
        let pb = makePasteboard()
        pb.setString("original", forType: .string)
        let snapshot = PasteboardSnapshot(of: pb)

        snapshot.restore(to: pb)
        pb.setString("changed", forType: .string)
        snapshot.restore(to: pb)

        #expect(pb.string(forType: .string) == "original")
        pb.releaseGlobally()
    }
}
