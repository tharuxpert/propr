import Foundation
import Testing

@testable import Propr

/// The bar and Quick Lookup each have their own custom instructions, injected the
/// same way. These pin down the framing, the storage cap and that the two are
/// genuinely separate settings.
struct CustomInstructionsTests {
    private let text = "Define each meaning on its own line."

    private func selection() -> ModelSelection {
        ModelSelection(
            id: UUID(), displayName: "Test Model", endpointID: UUID(),
            modelName: "test-model", baseURL: "https://api.example.com/v1")
    }

    @Test("Preferences are framed as the user's standing wishes")
    func framing() {
        let framed = CustomInstructions.instruction(text)
        #expect(framed.contains("<user_preferences>\n\(text)\n</user_preferences>"))
        #expect(framed.contains("unless the instruction asks for something different"))
    }

    @Test("Blank preferences are not appended at all")
    func blank() {
        #expect(CustomInstructions.appended("", to: "base") == "base")
        #expect(CustomInstructions.appended("  \n ", to: "base") == "base")
        #expect(CustomInstructions.appended(text, to: "base")
            == "base\n\n" + CustomInstructions.instruction(text))
    }

    @Test("Both the bar and the lookup get the same instructions injected")
    func injectedOnBothPaths() {
        var refine = ChatCompletionRequest(
            original: "hello", instruction: "make it formal", selection: selection(),
            apiKey: "", stream: false)
        refine.customInstructions = text
        #expect(refine.systemPrompt.hasSuffix(CustomInstructions.instruction(text)))

        var lookup = AILookupRequest(
            query: "hello", selection: selection(), apiKey: "", imageContext: nil)
        lookup.customInstructions = text
        #expect(lookup.systemPrompt.hasSuffix(CustomInstructions.instruction(text)))

        // Each prompt keeps its own base, so lookup is not answering with the
        // refine wording and vice versa.
        #expect(refine.systemPrompt.hasPrefix(ChatCompletionRequest.refineSystemPrompt))
        #expect(lookup.systemPrompt.hasPrefix(AILookupRequest.lookupSystemPrompt))
    }

    @Test("The bar's and the lookup's instructions are separate settings")
    func separateKeys() {
        #expect(CustomInstructions.refineKey != CustomInstructions.lookupKey)
        #expect(RefinePreferences.customInstructionsKey == CustomInstructions.refineKey)
        #expect(LookupPreferences.customInstructionsKey == CustomInstructions.lookupKey)
        #expect(RefinePreferences.customInstructionsLimit == CustomInstructions.limit)
    }

    @Test("Stored instructions are capped to the limit")
    func storedIsCapped() {
        let key = "test.customInstructions"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        UserDefaults.standard.set(
            String(repeating: "a", count: CustomInstructions.limit + 50), forKey: key)
        #expect(CustomInstructions.stored(under: key).count == CustomInstructions.limit)
        #expect(CustomInstructions.stored(under: "test.notSet").isEmpty)
    }
}
