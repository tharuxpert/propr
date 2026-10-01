import CoreGraphics
import Testing
@testable import Propr

struct PointerOCRTests {
    @Test("Crop follows pointer on a non-primary display")
    func secondaryDisplay() throws {
        let frame = CGRect(x: -1920, y: 100, width: 1920, height: 1080)
        let crop = try #require(PointerCaptureGeometry(
            appKitPoint: CGPoint(x: -1420, y: 800),
            screenFrame: frame,
            preferredSize: CGSize(width: 400, height: 200)))
        #expect(crop.sourceRect == CGRect(x: 300, y: 280, width: 400, height: 200))
        #expect(abs(crop.normalizedPointer.x - 0.5) < 0.001)
        #expect(abs(crop.normalizedPointer.y - 0.5) < 0.001)
    }

    @Test("Crop clips at display edge without moving the target")
    func clippedEdge() throws {
        let crop = try #require(PointerCaptureGeometry(
            appKitPoint: CGPoint(x: 10, y: 990),
            screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 1000),
            preferredSize: CGSize(width: 400, height: 200)))
        #expect(crop.sourceRect == CGRect(x: 0, y: 0, width: 210, height: 110))
        #expect(abs(crop.normalizedPointer.x - 10 / 210) < 0.001)
        #expect(abs(crop.normalizedPointer.y - (1 - 10 / 110)) < 0.001)
    }

    @Test("Only a word under the pointer is returned")
    func exactWord() {
        let words = [
            PointerRecognizedWord(text: "other", bounds: CGRect(x: 0.1, y: 0.7, width: 0.1, height: 0.1)),
            PointerRecognizedWord(text: "clicked", bounds: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1))
        ]
        #expect(PointerRecognizedWord.atPointer(
            CGPoint(x: 0.5, y: 0.5), in: words, sourceSize: CGSize(width: 400, height: 200)) == "clicked")
        #expect(PointerRecognizedWord.atPointer(
            CGPoint(x: 0.8, y: 0.5), in: words, sourceSize: CGSize(width: 400, height: 200)) == nil)
    }

    @Test("Pixel density does not change the point-space hit test")
    func retina() {
        let word = PointerRecognizedWord(
            text: "retina", bounds: CGRect(x: 0.48, y: 0.47, width: 0.08, height: 0.1))
        let logicalSize = CGSize(width: 400, height: 200)
        #expect(PointerRecognizedWord.atPointer(
            CGPoint(x: 0.5, y: 0.5), in: [word], sourceSize: logicalSize) == "retina")
    }
}
