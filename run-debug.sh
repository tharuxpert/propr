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

if [ ! -d "$APP_PATH" ]; then
    echo "→ Stable debug build not found at $APP_PATH"
    echo "→ Building now using xcodebuild (this will trigger the post-build copy script)..."
    
    xcodebuild -project Propr.xcodeproj -scheme Propr -configuration Debug build
    
    # The postBuildScript in project.yml *should* have copied it, but it can be flaky
    # with xcodebuild from terminal. We guarantee it here as a fallback.
    DERIVED_APP="$HOME/Library/Developer/Xcode/DerivedData/Propr-*/Build/Products/Debug/Propr.app"
    
    if [ ! -d "$APP_PATH" ]; then
        echo "→ Post-build copy script didn't create the stable app. Doing it manually now..."
        
        # Find the most recent built app in DerivedData
        LATEST_BUILT=$(ls -td $HOME/Library/Developer/Xcode/DerivedData/Propr-*/Build/Products/Debug/Propr.app 2>/dev/null | head -1)
        
        if [ -z "$LATEST_BUILT" ] || [ ! -d "$LATEST_BUILT" ]; then
            echo "Error: Could not find a built Propr.app in DerivedData."
            echo "Build output location may have changed. Please build once from Xcode (⌘B) first."
            exit 1
        fi
        
        mkdir -p "$(dirname "$APP_PATH")"
        rm -rf "$APP_PATH"
        cp -R "$LATEST_BUILT" "$APP_PATH"
        
        # Re-sign the copy
        codesign --force --deep --sign - "$APP_PATH" 2>/dev/null || true
        
        echo "✅ Manually copied stable build to: $APP_PATH"
    fi
fi

echo "→ Launching stable debug build from: $APP_PATH"
open "$APP_PATH"