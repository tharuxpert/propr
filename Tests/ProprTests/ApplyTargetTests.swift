import Testing

@testable import Propr

struct ApplyTargetTests {
    @MainActor
    @Test("An app without a focused AX element keeps its captured source PID")
    func missingElementKeepsCapturedPID() {
        let controller = FloatingBarController()
        controller.applyTargetElement = nil
        controller.applyTargetPID = 42_424
        controller.applyStrategy = .accessibility

        let target = controller.capturedTargetForApply()

        #expect(target.element == nil)
        #expect(target.pid == 42_424)
        #expect(target.strategy == .clipboardPaste)
    }
}
