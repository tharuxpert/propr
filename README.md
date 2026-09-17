# Propr

Lightweight native macOS menu bar app for instant AI text refinement anywhere.

Propr lives in your menu bar. Double-tap the **Command** key in any app and a floating bar appears, letting you refine or rewrite the text you're working on with AI. The improved version is applied back to the original field with a smooth, character-by-character typing animation.

## Features

- Menu bar only (no Dock icon)
- Summon from anywhere with a double-tap of the Command key
- Reads the focused text field (or your current selection) via the Accessibility API
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
4. The result is typed back into the field you came from. Use **Undo** in the bar if you don't like it.

Propr only reads your text at the moment you summon it. It does not watch what you type.

## Where your API keys are stored

API keys are stored in the **macOS Keychain**, under the service `com.tharuxpert.Propr.llm-keys`, one item per endpoint. They are marked device-only and are never synced to iCloud.

Everything else — your endpoints, model list and current selection — lives in plaintext JSON at `~/Library/Application Support/Propr/models.json`. That file contains no secrets.

Your text and keys go directly from your Mac to whichever provider you configured. Propr has no backend and sends nothing anywhere else.

## Developing

Grant Accessibility permission to the stable build at `Build/Debug/Propr.app` and use `./run-debug.sh` rather than Xcode's Run button.

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
