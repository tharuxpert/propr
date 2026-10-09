import AppKit
import Testing

@testable import Propr

struct SelectionCaptureTests {
    @Test("Lookup capture never selects and copies an entire field")
    func lookupIsSelectionOnly() {
        #expect(SelectionCapturePolicy.lookupSelection.allowsWholeFieldCopy == false)
        #expect(SelectionCapturePolicy.refinementContext.allowsWholeFieldCopy)
    }

    @MainActor
    @Test("A pre-click selection can only match a point inside its bounds")
    func preClickRequiresMatchingRegion() {
        let screenHeight = NSScreen.screens.first?.frame.maxY ?? 900
        let bounds = CGRect(x: 100, y: 200, width: 80, height: 20)

        #expect(SelectionCaptureService.selectionBounds(
            bounds, contain: CGPoint(x: 120, y: screenHeight - 210)))
        #expect(!SelectionCaptureService.selectionBounds(
            bounds, contain: CGPoint(x: 250, y: screenHeight - 210)))
        #expect(!SelectionCaptureService.selectionBounds(
            nil, contain: CGPoint(x: 120, y: screenHeight - 210)))
    }

    @MainActor
    @Test("A pre-click selection belongs only to its gesture and source app")
    func preClickOwnership() {
        let gesture = UUID()
        let screenHeight = NSScreen.screens.first?.frame.maxY ?? 900
        let snapshot = SelectionCaptureService.PreClickSelection(
            gestureID: gesture,
            pid: 1234,
            text: "selected phrase",
            bounds: CGRect(x: 100, y: 200, width: 80, height: 20),
            point: CGPoint(x: 120, y: screenHeight - 210),
            time: 10
        )

        #expect(snapshot.matches(gestureID: gesture, pid: 1234, now: 10.5))
        #expect(!snapshot.matches(gestureID: UUID(), pid: 1234, now: 10.5))
        #expect(!snapshot.matches(gestureID: gesture, pid: 5678, now: 10.5))
        #expect(!snapshot.matches(gestureID: gesture, pid: 1234, now: 11.1))
    }

    @MainActor
    @Test("Pointer fallback extracts only the clicked word")
    func clickedWord() {
        let sentence = "approval and rejection 👋🏽"
        #expect(SelectionCaptureService.word(
            in: sentence, atUTF16Offset: "approval and re".utf16.count) == "rejection")
        #expect(SelectionCaptureService.word(
            in: sentence, atUTF16Offset: "approval".utf16.count) == nil)
        #expect(SelectionCaptureService.word(
            in: sentence, atUTF16Offset: "approval and rejection ".utf16.count) == nil)
    }
}
