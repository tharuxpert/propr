#!/bin/zsh
# Convenience script to launch the stable debug build.
# This is the recommended (and only supported) way to run Propr during development.
#
# It does several things to reduce Accessibility (TCC) pain:
#   - Always builds to a stable path: Build/Debug/Propr.app
#   - Kills any running instance before building
#   - Only resets TCC on clean builds (mode 3). Normal builds reuse the existing
#     permission because the app is always at the exact same stable path.
#
# CRITICAL: Never use Xcode's Run button (⌘R) for this app during development.
#
# Usage:
#   ./run-debug.sh          # or ./run-debug.sh 1   → Just open the app (no build)
#   ./run-debug.sh 2        # or --build            → Build (incremental) + launch (keeps existing Accessibility permission)
#   ./run-debug.sh 3        # or --clean            → Clean + build + reset TCC + launch (fresh permission prompt)

set -e

MODE=${1:-1}
APP_PATH="Build/Debug/Propr.app"
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"

cd "$PROJECT_ROOT"

run_xcodegen() {
    if command -v xcodegen >/dev/null 2>&1; then
        echo "→ Regenerating Xcode project..."
        xcodegen generate
    else
        echo "Warning: xcodegen not found. Skipping regeneration."
    fi
}

do_build() {
    local clean=$1

    # Kill any running instance first (prevents TCC weirdness)
    echo "→ Quitting any running Propr instance..."
    pkill -x Propr 2>/dev/null || true
    sleep 0.5

    if [[ "$clean" == "true" ]]; then
        # Only reset TCC on clean builds. This gives you a completely fresh permission state.
        echo "→ Cleaning old Accessibility permission entries (clean build)..."
        tccutil reset Accessibility com.tharuxpert.Propr 2>/dev/null || true
    else
        echo "→ Incremental build — keeping existing Accessibility permission (if any)."
    fi

    run_xcodegen

    if [[ "$clean" == "true" ]]; then
        echo "→ Cleaning and building (this may take a while)..."
        xcodebuild -project Propr.xcodeproj -scheme Propr -configuration Debug clean build
    else
        echo "→ Building (incremental)..."
        xcodebuild -project Propr.xcodeproj -scheme Propr -configuration Debug build
    fi

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

    # Re-sign the stable copy
    codesign --force --deep --sign - "$APP_PATH" 2>/dev/null || true

    echo ""
    echo "✅ Stable build updated at:"
    echo "   $APP_PATH"
    echo ""

    if [[ "$clean" == "true" ]]; then
        echo "IMPORTANT FOR ACCESSIBILITY PERMISSION:"
        echo "  → TCC was reset for this clean build."
        echo "  → You will get a fresh prompt when you launch."
        echo "  → Grant permission ONLY to this exact stable path:"
        echo "    $APP_PATH"
        echo ""
        echo "→ Opening Accessibility settings for you..."
        open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    else
        echo "NOTE: Accessibility permission should be preserved from previous runs"
        echo "      (because the app is always at the same stable path)."
        echo "      If it asks again, grant it to: $APP_PATH"
    fi

    echo ""
    echo "  → Never use Xcode's Run button (⌘R) — always use this script."
    echo ""
}

case "$MODE" in
    -h|--help|help)
        echo "Usage: $0 [1|2|3|--open|--build|--clean]"
        echo ""
        echo "  1, --open, (default)   Just launch the stable app (fastest)"
        echo "  2, --build             Build (incremental) + launch (keeps existing Accessibility permission)"
        echo "  3, --clean             Clean + build + reset TCC + fresh permission prompt"
        echo ""
        echo "TCC / Accessibility handling:"
        echo "  - Normal builds (mode 2) do NOT reset permission (stable path = permission sticks)."
        echo "  - Clean builds (mode 3) reset TCC so you get a fresh prompt."
        exit 0
        ;;
    1|--open|-o|"")
        echo "→ Launching existing stable build (no build)..."
        ;;
    2|--build|-b)
        do_build false
        ;;
    3|--clean|-c)
        do_build true
        ;;
    *)
        echo "Usage: $0 [1|2|3|--open|--build|--clean]"
        echo ""
        echo "  1, --open, (default)   Just launch the stable app"
        echo "  2, --build             Build (incremental) + launch"
        echo "  3, --clean             Clean + build + reset TCC + launch"
        exit 1
        ;;
esac

if [ ! -d "$APP_PATH" ]; then
    echo "Error: $APP_PATH does not exist."
    echo "Run with mode 2 or 3 first to build it."
    exit 1
fi

echo "→ Launching: $APP_PATH"
open "$APP_PATH"