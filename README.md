# Propr

Lightweight native macOS menu bar app for instant AI text refinement anywhere.

Propr lives in your menu bar. When you focus a text field in any app, a clean floating bar appears, letting you refine or rewrite your text with AI. Apply the improved version back to the original field with a smooth, character-by-character typing animation.

## Features

- Menu bar only (no Dock icon)
- System-wide focused text field detection via the Accessibility API
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

After launching, Propr appears as an icon in the menu bar. Focus any text field in any app and the refinement interface should appear near it.

## Contributing

Contributions are welcome!

Feel free to open an issue or submit a pull request. For larger changes, it's a good idea to discuss the approach in an issue first.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
