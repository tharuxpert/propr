#!/bin/zsh
# Sign an app bundle with a *stable* code signing identity.
#
# Why this exists
# ---------------
# macOS binds Keychain item ACLs and TCC permission grants (Accessibility,
# Input Monitoring, ...) to an app's designated requirement (DR), not to its
# path. An ad-hoc signature has no identity, so codesign falls back to making
# the DR the cdhash itself:
#
#   designated => cdhash H"554b8d3f2d2204c0873f69d86b319c37ba8fdfbb"
#
# The cdhash changes on every build, so every grant is invalidated by
# construction — which is why this project used to reset TCC on every run.
# Signing with a real certificate produces an identity-based DR instead:
#
#   designated => identifier "com.tharuxpert.Propr" and anchor apple generic
#                 and certificate leaf[subject.CN] = "..."
#
# That DR is byte-identical across rebuilds, so grants survive.
#
# No paid Apple Developer account is required. Apple TN2206: signature
# stability "is determined through the designated requirement (DR) mechanism,
# and does not depend on the nature of the certificate authority used. The
# keychain system and parental controls are examples of such usage.
# Self-signed identities and homemade certificate authorities (CA) work by
# default for this case."
#
# Usage: scripts/sign-app.sh <path-to-.app>

set -eu

APP="${1:-}"
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
    echo "usage: $0 <path-to-.app>" >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Identity resolution — first match wins. Deliberately explicit: we never
# auto-pick an arbitrary certificate out of the keychain, because on a machine
# with several identities that silently picks someone else's name.
#
#   1. $PROPR_SIGN_IDENTITY        — explicit override
#   2. $CODE_SIGN_IDENTITY         — inherited from the Xcode build environment
#   3. Configs/Signing.local.xcconfig — the per-machine config Xcode also reads
#   4. ad-hoc — status quo, with a warning
#
# Configs/Signing.local.xcconfig is the single source of truth: Xcode reads it
# via Configs/Signing.xcconfig, and this script parses the same value so the
# identity never has to be configured in two places.
resolve_identity() {
    if [ -n "${PROPR_SIGN_IDENTITY:-}" ]; then
        printf '%s' "$PROPR_SIGN_IDENTITY"
        return
    fi

    # Set when running as an Xcode build phase. "-" means Xcode is ad-hoc signing.
    if [ -n "${CODE_SIGN_IDENTITY:-}" ] && [ "${CODE_SIGN_IDENTITY}" != "-" ]; then
        printf '%s' "$CODE_SIGN_IDENTITY"
        return
    fi

    local xcconfig="$REPO_ROOT/Configs/Signing.local.xcconfig"
    if [ -f "$xcconfig" ]; then
        local from_config
        from_config=$(sed -n 's/^[[:space:]]*CODE_SIGN_IDENTITY[[:space:]]*=[[:space:]]*//p' "$xcconfig" | tail -1)
        # Trim trailing whitespace; ignore an explicit ad-hoc value.
        from_config="${from_config%"${from_config##*[![:space:]]}"}"
        if [ -n "$from_config" ] && [ "$from_config" != "-" ]; then
            printf '%s' "$from_config"
            return
        fi
    fi

    printf '%s' "-"
}

IDENTITY="$(resolve_identity)"

# Sign inside-out: nested code first, then the bundle. (Apple discourages
# --deep for signing; it does not sign nested code the way a correct
# inside-out pass does.)
sign_one() {
    # Keep codesign's own message: it is the only thing that says *why* a sign failed.
    local output
    if ! output=$(codesign --force --timestamp=none --sign "$IDENTITY" "$1" 2>&1); then
        echo "$output" >&2
        return 1
    fi
    return 0
}

if [ "$IDENTITY" = "-" ]; then
    echo "⚠️  No stable signing identity configured — falling back to ad-hoc."
    echo "    Accessibility permission and Keychain access will NOT survive rebuilds."
    echo "    Fix: add to Configs/Signing.local.xcconfig"
    echo "         CODE_SIGN_IDENTITY = Your Identity Name"
    echo "    List candidates with: security find-identity -v -p codesigning"
else
    echo "→ Signing with stable identity: $IDENTITY"
fi

# Nested dylibs / frameworks first.
while IFS= read -r nested; do
    [ -n "$nested" ] || continue
    sign_one "$nested" || {
        echo "Error: failed to sign nested code: $nested" >&2
        exit 1
    }
done <<EOF
$(find "$APP/Contents" -type f -name "*.dylib" 2>/dev/null)
EOF

while IFS= read -r fw; do
    [ -n "$fw" ] || continue
    sign_one "$fw" || {
        echo "Error: failed to sign framework: $fw" >&2
        exit 1
    }
done <<EOF
$(find "$APP/Contents" -type d -name "*.framework" 2>/dev/null)
EOF

# Then the app bundle itself.
if ! sign_one "$APP"; then
    echo "Error: failed to sign $APP with identity '$IDENTITY'" >&2
    exit 1
fi

if [ "$IDENTITY" != "-" ]; then
    # Surface the DR so it is obvious whether the signature is stable.
    # codesign -d writes its report to stderr, hence 2>&1. It prints
    # "designated => ..." for an explicit identity but "# designated => ..."
    # (commented, because implicit) for ad-hoc, so both forms are matched.
    DR=$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^#* *designated => //p')
    case "$DR" in
        cdhash*)
            echo "⚠️  DR is still cdhash-based — permissions will not persist:"
            echo "    $DR"
            ;;
        *)
            echo "   DR: $DR"
            ;;
    esac
fi
