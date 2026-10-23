# Propr — agent notes

## Always rebuild the app after changing code

Run this after **every** code change, without asking first:

```bash
./run-debug.sh 2
```

This is a deliberate exception to the global "do not run large or time-consuming build
commands unless explicitly requested" default. The user works in the running app, so a
change that has not been rebuilt has not been delivered.

### Why it is not optional

- `Build/Debug/Propr.app` is the copy the user actually uses, and the copy that holds
  the Accessibility grant.
- A bare `xcodebuild`, or Xcode's Run button (⌘R), updates **only** DerivedData. The
  stable copy then silently goes stale and the change looks as though it did nothing.
- So never use ⌘R for this app. `./run-debug.sh` is the only supported way to run it.

### What the script does

- Quits the running instance first, so **the app restarts on every rebuild** — any open
  floating bar, Lookup panel or Settings window goes with it.
- Regenerates `Propr.xcodeproj` from `project.yml` with `xcodegen`, then builds.
- Copies the product to `Build/Debug/Propr.app` and re-signs it with the stable identity
  from `Configs/Signing.local.xcconfig` (gitignored, per-machine), which is what keeps
  the Accessibility and Keychain grants valid across rebuilds.
- Without that file it falls back to ad-hoc signing, and the Accessibility grant has to
  be re-granted after every build.

Modes: `./run-debug.sh 2` builds incrementally, `3` does a clean build, `1` just
relaunches the existing build. Add `--reset-tcc` to clear a genuinely stale Accessibility
entry.

A markdown- or config-only change that does not touch `Sources/` needs no rebuild.

## Delegated work

Which model to delegate to, and what stays with the main agent (reviews, planning, tricky
logic, final verification), are in the global instructions. What is specific to this repo:

- **Give children the constraints:** Swift 6 with `SWIFT_STRICT_CONCURRENCY: complete`,
  macOS 14 deployment target, not sandboxed.
- **Children do not run `./run-debug.sh`.** It quits and relaunches the app the user is
  working in. The main agent rebuilds once the result is checked and applied.
- **Verify their claims rather than relaying them.** Past misses from a second model on
  this repo: it asserted that `addModels` enforced an alias rule `canAddDraftModel` actually
  permits, and claimed a byte-loop read cost "seconds" when measurement showed ~30 ms for
  778 KB.

## Other build facts

- Tests:
  `xcodebuild -project Propr.xcodeproj -scheme Propr -destination 'platform=macOS' test`
- Adding or removing files under `Sources/` or `Tests/` requires `xcodegen generate`
  before building, because `Propr.xcodeproj` is generated from `project.yml` and the
  generated project is committed for clone-and-open. `run-debug.sh` runs it for you.
- Changing a **build setting** in `project.yml` likewise requires regenerating first.
