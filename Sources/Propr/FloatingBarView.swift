import AppKit
import Pow
import SwiftUI

/// The actual floating bar UI shown inside the NSPanel.
/// Minimal summon-only design.
struct FloatingBarView: View {
    let snapshot: FieldSnapshot
    @ObservedObject var sessionState: FloatingBarSessionState

    let onRefine: (String, RefineIntent) -> Void
    let onStop: () -> Void
    let onClose: () -> Void
    var onUndo: (() -> Void)? = nil
    /// Reports the content's natural height whenever it changes, so the panel can
    /// be sized to it. SwiftUI measures it; the panel does not size itself.
    var onContentHeightChange: ((CGFloat) -> Void)? = nil

    @State var prompt: String = ""
    @FocusState var isPromptFocused: Bool
    @Namespace var glassNamespace
    @AppStorage(QuickPrompts.key) var quickPrompts = QuickPrompts.defaults
    /// Keeps the pills' space for a moment after they hide, so the panel does not
    /// shrink under them while they flow back into the bar.
    @State var holdsQuickPromptSpace = false
    /// Whether the pills are out. Trails `showsQuickPrompts` on the way in, until
    /// the panel has grown to make room for them.
    @State var revealsQuickPrompts = false
    /// The mode whose pills are out. Trails the bar's mode while one set swaps
    /// for the other.
    @State var displayedQuickPromptMode: QuickPrompt.Mode = .edit
    /// A quick prompt flying into the composer, until it is sent.
    @State var quickPromptStamp: QuickPromptStamp?
    /// Counts stamps landing, so each one sets off the landing effects.
    @State var quickPromptLandings = 0
    /// Where each pill's text and the composer's text start, in stage coordinates:
    /// the two ends of a stamp's flight.
    @State var pillTextOrigins: [UUID: CGPoint] = [:]
    @State var promptTextOrigin: CGPoint?
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var displayedContextText: String {
        sessionState.latestAppliedText ?? snapshot.contextText
    }

    /// One line of the text being refined. Newlines are flattened so a multi-line
    /// field still previews as a single line; the prefix keeps layout cheap.
    private var textPreview: String {
        String(displayedContextText.prefix(300))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(spacing: 0) {
            bar
            // Animated on its own, so the pills' spring never slows the rest of the
            // bar: the placeholder and the tab hint still change at once.
            quickPromptArea
        }
        .modifier(GlassGroup(spacing: Self.glassBlendSpacing))
        .coordinateSpace(.named(QuickPromptStamp.stage))
        .overlay(alignment: .topLeading) {
            if let quickPromptStamp {
                QuickPromptStampFlight(stamp: quickPromptStamp)
            }
        }
        // The whole bar, glass and all, takes the hit when a stamp lands.
        .changeEffect(.shake(rate: .fast), value: quickPromptLandings)
        // Natural height, whatever frame the panel currently has.
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            onContentHeightChange?(height)
        }
        // Pinned to the top. The panel catches up with a change in height a pass
        // later, and until then the hosting view would centre the content in the
        // old frame, jumping the bar up and back down.
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            holdsQuickPromptSpace = showsQuickPrompts
            revealsQuickPrompts = showsQuickPrompts
            displayedQuickPromptMode = quickPromptMode
        }
        .onChange(of: sessionState.isAskMode) {
            quickPromptModeChanged()
        }
        .onChange(of: showsQuickPrompts) { _, shows in
            quickPromptVisibilityChanged(to: shows)
        }
    }

    /// The bar itself: the source strip, the composer and whatever the last request
    /// produced.
    private var bar: some View {
        VStack(spacing: 0) {
            // One even inset, roughly the corner radius, so the keys in the corners
            // never crowd the rounding.
            FloatingBarSourceStrip(
                appName: snapshot.appName,
                pid: snapshot.pid,
                preview: textPreview,
                onClose: onClose
            )
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .padding(.top, 12)

            composerRow
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .padding(.top, 10)
                .padding(.bottom, 12)

            if let answer = sessionState.answer {
                AnswerSection(answer: answer)
            }

            if let error = sessionState.errorMessage {
                RefineErrorBanner(message: error) { sessionState.clearError() }
            }

            if let notice = sessionState.noticeMessage {
                RefineNoticeBanner(message: notice) { sessionState.clearNotice() }
            }
        }
        .frame(maxWidth: .infinity)
        .modifier(DraggablePanel())
        // The panel itself is borderless and clear; the backdrop and rounding live here.
        .modifier(
            FloatingBarSurface(
                cornerRadius: Self.cornerRadius,
                isBusy: sessionState.isBusy,
                glassNamespace: glassNamespace
            )
        )
    }

    /// Matches the rounding macOS uses on floating panels of this size.
    private static let cornerRadius: CGFloat = 16

    /// How near the pills and the bar must be before their glass flows together.
    /// Narrower than the gap between them, so they merge only while moving in and
    /// out; at rest the bar's own shape stays exactly as it is.
    private static let glassBlendSpacing: CGFloat = 6
}

#Preview("Floating Bar") {
    FloatingBarView(
        snapshot: FieldSnapshot(
            appName: "Notes",
            pid: 1234,
            fullText:
                "This is some text I wrote quickly and now I want to make it sound better for a blog post or an important email to my team.",
            selectedText: nil,
            role: kAXTextAreaRole as String
        ),
        sessionState: FloatingBarSessionState(),
        onRefine: { _, _ in },
        onStop: {},
        onClose: {}
    )
    .padding(40)
    .background(Color.black.opacity(0.6))
}
