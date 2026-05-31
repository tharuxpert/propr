#!/bin/zsh
# Convenience script to launch the stable debug build.
# This is the recommended way to run Propr during development
# so that Accessibility permission survives rebuilds.

set -e

APP_PATH="Build/Debug/Propr.app"
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"

cd "$PROJECT_ROOT"

# Always regenerate the project first so postBuildScripts (the copy to stable location)
# are up to date. This prevents the "Build/Debug/Propr.app does not exist" problem
# when project.yml has been edited.
if command -v xcodegen >/dev/null 2>&1; then
    echo "→ Regenerating Xcode project (xcodegen generate)..."
    xcodegen generate
else
    echo "Warning: xcodegen not found in PATH. Skipping regeneration."
    echo "If you recently edited project.yml, run 'xcodegen generate' manually first."
fi

echo "→ Building (xcodebuild will do incremental build if nothing changed)..."

xcodebuild -project Propr.xcodeproj -scheme Propr -configuration Debug build

# Always refresh the stable copy after build (even if it already existed).
# This ensures the latest code is in Build/Debug/Propr.app for stable Accessibility permissions.
echo "→ Updating stable debug build at $APP_PATH ..."

LATEST_BUILT=$(ls -td $HOME/Library/Developer/Xcode/DerivedData/Propr-*/Build/Products/Debug/Propr.app 2>/dev/null | head -1)

if [ -z "$LATEST_BUILT" ] || [ ! -d "$LATEST_BUILT" ]; then
    echo "Error: Could not find a built Propr.app after build."
    echo "Please try building once from Xcode (⌘B) first."
    exit 1
fi

mkdir -p "$(dirname "$APP_PATH")"
rm -rf "$APP_PATH"
cp -R "$LATEST_BUILT" "$APP_PATH"

# Re-sign the copy (helps with some TCC edge cases)
codesign --force --deep --sign - "$APP_PATH" 2>/dev/null || true

echo "✅ Stable build updated at: $APP_PATH"

echo "→ Launching stable debug build from: $APP_PATH"
open "$APP_PATH"