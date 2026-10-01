# Propr

Lightweight native macOS menu bar app for AI text refinement and quick lookup anywhere.

Propr lives in your menu bar. Double-tap the **Command** key in any app to refine or rewrite text with AI, then apply it back to the original field. Tap **Fn** or use a genuine trackpad **Force Click** to look up selected text in a separate floating search panel without changing the source text.

## Features

- Menu bar only (no Dock icon)
- Summon the refinement bar with a double-tap of the Command key
- Reads the focused text field (or your current selection) via the Accessibility API
- Look up a selection with Fn or Force Click in a separate, read-only search panel
- Edit the search query and switch between Google, DuckDuckGo, and your configured AI model
- Beautiful first-run onboarding with proper permission handling
- Floating refinement panel with editable context
- Direct "Open System Settings" flow for Accessibility permission
- One-click apply with natural typing animation

## Building from Source

### Requirements

- macOS 14 (Sonoma) or later
- Xcode 16 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/tharuxpert/propr.git
   cd propr
   ```

2. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```

3. Open the generated project:
   ```bash
   open Propr.xcodeproj
   ```

4. Build and run (⌘R in Xcode).

On first launch, macOS will request Accessibility permission. This is required for Propr to detect text fields across all applications.

## Usage

After launching, Propr appears as an icon in the menu bar. It stays out of the way until you ask for it.

1. Put the cursor in any text field, or select some text.
2. **Double-tap the Command key.** The bar appears in the centre of the screen. (You can also use *Show Floating Bar* from the menu bar icon.)
3. Type what you want done — "make this more concise", "fix the grammar", "rewrite as a polite reply" — and press Return.
4. The result is typed back into the field you came from. You can send follow-up instructions or use **Undo** in the bar.

For a lookup, select text and tap **Fn**, or press firmly on a Force Touch trackpad. The dark search panel opens separately from the refinement bar and does not replace the selected text. It searches the selection automatically; you can edit the query or choose Google, DuckDuckGo, or AI. If no text can be captured, type a query into the panel. Force Click requires a trackpad that produces a genuine pressure event; an ordinary click does not open search.

Lookup uses the current selection or, for Force Click, text at the pressed position when available. It does not select and copy an entire field as a fallback. Screenshot capture is not currently connected to search.

## Where your API keys are stored

API keys are stored in the **macOS Keychain**, under the service `com.tharuxpert.Propr.llm-keys`, one item per endpoint. They are marked device-only and are never synced to iCloud.

Everything else — your endpoints, model list and current selection — lives in plaintext JSON at `~/Library/Application Support/Propr/models.json`. That file contains no secrets.

Refinement text and your API key go directly from your Mac to the AI endpoint you configured. In the search panel, a web lookup sends the current query to the selected web provider (Google or DuckDuckGo). Choosing AI sends the current query to your configured AI endpoint using the selected model and its Keychain-stored key. Propr has no backend.

## Developing

Grant Accessibility permission to the stable build at `Build/Debug/Propr.app` and use `./run-debug.sh` rather than Xcode's Run button.

`./run-debug.sh` is what refreshes that stable copy — a bare `xcodebuild` or an Xcode build updates only the product in DerivedData, so `Build/Debug/Propr.app` will silently still be the previous build.

macOS ties both Accessibility grants and Keychain access to an app's code signature, so the debug build is signed with a stable identity — otherwise every rebuild looks like a different app and you re-grant permission each time. No paid Apple Developer account is needed; any code signing certificate works, including a self-signed one.

Set yours once:

```bash
security find-identity -v -p codesigning   # list candidates
```

Then create `Configs/Signing.local.xcconfig` (gitignored, per-machine):

```
CODE_SIGN_IDENTITY = Apple Development: Your Name (TEAMID)
```

Without that file the build falls back to ad-hoc signing and still works, but permissions will not survive rebuilds.

## Contributing

Contributions are welcome!

Feel free to open an issue or submit a pull request. For larger changes, it's a good idea to discuss the approach in an issue first.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
