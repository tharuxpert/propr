import AppKit
import ScreenCaptureKit
import Vision

/// A last-resort lookup for rendered text with no usable Accessibility text.
/// Screenshots stay in memory and are never sent to a server.
@MainActor
enum PointerOCRService {
    enum LookupResult: Equatable {
        case word(String)
        case permissionRequired
        case noWord
    }

    static func lookupWord(at appKitPoint: CGPoint) async -> LookupResult {
        guard CGPreflightScreenCaptureAccess() else { return .permissionRequired }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(appKitPoint) }),
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
            let geometry = PointerCaptureGeometry(
                appKitPoint: appKitPoint,
                screenFrame: screen.frame,
                preferredSize: CGSize(width: 420, height: 220))
        else { return .noWord }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID })
            else { return .noWord }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = geometry.sourceRect
            let scale = max(1, CGFloat(filter.pointPixelScale))
            configuration.width = max(1, Int((geometry.sourceRect.width * scale).rounded()))
            configuration.height = max(1, Int((geometry.sourceRect.height * scale).rounded()))
            configuration.scalesToFit = false
            configuration.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration)
            let point = geometry.normalizedPointer
            let size = geometry.sourceRect.size
            let result = await Task.detached(priority: .userInitiated) {
                recognizeWord(in: image, at: point, sourceSize: size)
            }.value
            return result.map(LookupResult.word) ?? .noWord
        } catch {
            return .noWord
        }
    }

    private nonisolated static let tokenPattern = try! NSRegularExpression(
        pattern: "[\\p{L}\\p{N}_]+(?:['’.-][\\p{L}\\p{N}_]+)*"
    )

    private nonisolated static func recognizeWord(
        in image: CGImage,
        at point: CGPoint,
        sourceSize: CGSize
    ) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            return nil
        }

        var words: [PointerRecognizedWord] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            let matches = tokenPattern.matches(
                in: text,
                range: NSRange(location: 0, length: (text as NSString).length))
            for match in matches {
                guard let range = Range(match.range, in: text),
                    let bounds = try? candidate.boundingBox(for: range)?.boundingBox
                else { continue }
                words.append(PointerRecognizedWord(text: String(text[range]), bounds: bounds))
            }
        }
        return PointerRecognizedWord.atPointer(
            point, in: words, sourceSize: sourceSize)
    }
}

/// Source rectangles are display-local points with a top-left origin. Vision
/// rectangles are normalized with a bottom-left origin.
struct PointerCaptureGeometry {
    let sourceRect: CGRect
    let normalizedPointer: CGPoint

    init?(appKitPoint: CGPoint, screenFrame: CGRect, preferredSize: CGSize) {
        guard screenFrame.contains(appKitPoint), preferredSize.width > 0,
            preferredSize.height > 0 else { return nil }
        let localPoint = CGPoint(
            x: appKitPoint.x - screenFrame.minX,
            y: screenFrame.maxY - appKitPoint.y)
        let displayBounds = CGRect(origin: .zero, size: screenFrame.size)
        let proposed = CGRect(
            x: localPoint.x - preferredSize.width / 2,
            y: localPoint.y - preferredSize.height / 2,
            width: preferredSize.width,
            height: preferredSize.height)
        let crop = proposed.intersection(displayBounds)
        guard !crop.isNull, crop.width > 0, crop.height > 0 else { return nil }
        sourceRect = crop
        normalizedPointer = CGPoint(
            x: (localPoint.x - crop.minX) / crop.width,
            y: 1 - (localPoint.y - crop.minY) / crop.height)
    }
}

struct PointerRecognizedWord {
    let text: String
    let bounds: CGRect

    /// Small OCR box imprecision is tolerated, but an unrelated word elsewhere
    /// in the crop can never become the query.
    static func atPointer(
        _ normalizedPoint: CGPoint,
        in words: [PointerRecognizedWord],
        sourceSize: CGSize
    ) -> String? {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        let tolerance: CGFloat = 7
        let point = CGPoint(
            x: normalizedPoint.x * sourceSize.width,
            y: normalizedPoint.y * sourceSize.height)
        return words.compactMap { word -> (String, CGFloat)? in
            let box = CGRect(
                x: word.bounds.minX * sourceSize.width,
                y: word.bounds.minY * sourceSize.height,
                width: word.bounds.width * sourceSize.width,
                height: word.bounds.height * sourceSize.height)
            let dx = max(box.minX - point.x, 0, point.x - box.maxX)
            let dy = max(box.minY - point.y, 0, point.y - box.maxY)
            let distance = hypot(dx, dy)
            guard distance <= tolerance else { return nil }
            return (word.text, distance)
        }.min(by: { $0.1 < $1.1 })?.0
    }
}
