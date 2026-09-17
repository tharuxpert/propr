#!/bin/zsh
# Convenience script to launch the stable debug build.
# This is the recommended (and only supported) way to run Propr during development.
#
# It does several things to reduce Accessibility (TCC) pain:
#   - Always builds to a stable path: Build/Debug/Propr.app
#   - Kills any running instance before launching/building
#   - Signs the stable copy with a stable code signing identity, so macOS keeps
#     the Accessibility grant across rebuilds (see scripts/sign-app.sh).
#
# The TCC reset is no longer done on every run. It was only ever needed because
# ad-hoc signing changes the app's designated requirement on every build, which
# makes macOS treat each build as a different app. With a stable identity the
# grant persists, so resetting is now opt-in via --reset-tcc for when a genuinely
# stale entry needs clearing.
#
# CRITICAL: Never use Xcode's Run button (⌘R) for this app during development.
#
# Usage:
#   ./run-debug.sh          # or ./run-debug.sh 1   → open existing app
#   ./run-debug.sh 2        # or --build            → build (incremental) + launch
#   ./run-debug.sh 3        # or --clean            → clean build + launch
#   ./run-debug.sh 2 --reset-tcc                    → also clear the Accessibility entry

set -eu

MODE=1
RESET_TCC=false
for arg in "$@"; do
    case "$arg" in
        --reset-tcc) RESET_TCC=true ;;
        *) MODE="$arg" ;;
    esac
done
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

quit_running_app() {
    echo "→ Quitting any running Propr instance..."
    pkill -x Propr 2>/dev/null || true
    sleep 0.5
}

reset_accessibility_permission() {
    [[ "$RESET_TCC" == "true" ]] || return 0
    echo "→ Removing existing Accessibility permission entry (--reset-tcc)..."
    tccutil reset Accessibility com.tharuxpert.Propr 2>/dev/null || true
}

print_accessibility_notice() {
    if [[ "$RESET_TCC" != "true" ]]; then
        echo "→ Accessibility grant left intact (stable signature keeps it valid across rebuilds)."
        echo "  If the app reports missing permission, re-run with --reset-tcc and grant it to:"
        echo "    $APP_PATH"
        return 0
    fi

    echo "IMPORTANT FOR ACCESSIBILITY PERMISSION:"
    echo "  → Existing TCC Accessibility entry was removed."
    echo "  → Grant permission ONLY to this exact stable path:"
    echo "    $APP_PATH"
    echo ""
    echo "→ Opening Accessibility settings for you..."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
}

do_build() {
    local clean=$1

    quit_running_app
    reset_accessibility_permission

    run_xcodegen

    if [[ "$clean" == "true" ]]; then
        echo "→ Cleaning and building (this may take a while)..."
        xcodebuild -project Propr.xcodeproj -scheme Propr -configuration Debug -destination 'platform=macOS' clean build
    else
        echo "→ Building (incremental)..."
        xcodebuild -project Propr.xcodeproj -scheme Propr -configuration Debug -destination 'platform=macOS' build
    fi

    echo "→ Updating stable debug build at $APP_PATH ..."

    LATEST_BUILT=$(ls -td $HOME/Library/Developer/Xcode/DerivedData/Propr-*/Build/Products/Debug/Propr.app 2>/dev/null | head -1)

    if [ -z "$LATEST_BUILT" ] || [ ! -d "$LATEST_BUILT" ]; then
        echo "Error: Could not find a built Propr.app after build."
        echo "Please try building once from Xcode (⌘B) first."
        exit 1
    fi

    mkdir -p "$(dirname "$APP_PATH")"
    if [ -e "$APP_PATH" ]; then
        chmod -R u+w "$APP_PATH" 2>/dev/null || true
        rm -rf "$APP_PATH"
    fi
    ditto "$LATEST_BUILT" "$APP_PATH"

    # Re-sign the stable copy with a stable identity so the Accessibility grant
    # and any Keychain ACLs survive the rebuild. See scripts/sign-app.sh.
    "$PROJECT_ROOT/scripts/sign-app.sh" "$APP_PATH"

    echo ""
    echo "✅ Stable build updated at:"
    echo "   $APP_PATH"
    echo ""
    echo "  → Never use Xcode's Run button (⌘R) — always use this script."
    echo ""
}

case "$MODE" in
    -h|--help|help)
        echo "Usage: $0 [1|2|3|--open|--build|--clean] [--reset-tcc]"
        echo ""
        echo "  1, --open, (default)   Launch stable app"
        echo "  2, --build             Build (incremental) + launch"
        echo "  3, --clean             Clean build + launch"
        echo "  --reset-tcc            Also clear the Accessibility entry (opt-in)"
        echo ""
        echo "TCC / Accessibility handling:"
        echo "  - The stable copy is signed with a stable identity, so the Accessibility"
        echo "    grant survives rebuilds and is NOT reset by default."
        echo "  - Configure the identity in Configs/Signing.local.xcconfig."
        exit 0
        ;;
    1|--open|-o|"")
        echo "→ Launching existing stable build (no build)..."
        quit_running_app
        reset_accessibility_permission
        ;;
    2|--build|-b)
        do_build false
        ;;
    3|--clean|-c)
        do_build true
        ;;
    *)
        echo "Usage: $0 [1|2|3|--open|--build|--clean] [--reset-tcc]"
        echo ""
        echo "  1, --open, (default)   Launch stable app"
        echo "  2, --build             Build (incremental) + launch"
        echo "  3, --clean             Clean build + launch"
        echo "  --reset-tcc            Also clear the Accessibility entry (opt-in)"
        exit 1
        ;;
esac

if [ ! -d "$APP_PATH" ]; then
    echo "Error: $APP_PATH does not exist."
    echo "Run with mode 2 or 3 first to build it."
    exit 1
fi

print_accessibility_notice

echo "→ Launching: $APP_PATH"
open "$APP_PATH"
