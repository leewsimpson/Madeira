# Madeira on iPhone Duo: Progress

Nov 15, 2026 · goes with [PLAN.md](PLAN.md) · branch `madeira-duo`

PC work for P0 to P5 is done and checked on Windows. Nothing has been built for or run on the Duo yet; device round 1 is next.

## Fast loop on Windows

```bash
. tools/host/env.sh          # Git Bash; PowerShell: . tools/host/env.ps1
python tests/host/check-duo-display.py
```

`check-frontend.py` now runs fully on Windows: it compiles the Swift harness with `swiftc` (the `swift file.swift` mode cannot link it there), shims `setenv`/`unsetenv` on Windows, and finds a C compiler through `CC`, `cc`, `gcc` or `clang`.

## What changed, by phase

| Phase | Change | Files |
| --- | --- | --- |
| P0 | `SDKROOT` helpers; `check-frontend` runs on Windows; new `check-duo-display.py` with golden values for eight current iPhones and iPads (recorded at fbad4304, before any change) and placeholder Duo screens; Duo screens added to the control-preset and library-zoom checks. | `tools/host/env.{sh,ps1}`, `tests/host/check-*.py` |
| P1 | `[display-geometry]` log line at launch and on every scene geometry (KVO on `effectiveGeometry`) or size-class change, plus scene connect/disconnect and screen connect/disconnect. | `DisplayGeometry.swift` (new, added to the Xcode project), `MadeiraApp.swift` |
| P2 | `ResolutionChoices.screen` is lock-protected and updatable: `update(_:)` follows the app scene's screen and posts `screenChanged` only when the shape changes (a rotation does not). The library's Resolution picker rebuilds on it. | `GuestDisplay.swift`, `DisplayGeometry.swift`, `Library.swift` |
| P3 | Stored tokens `"screen"` and `"screen@720"`, resolved when a game starts (`LibraryEntry.launchResolution`). The device remembers the screen shapes it has shown; only once it has shown two (a foldable) do new entries and recommendations store the token, and a one-time pass converts entries on a seen shape's default or 720-line size. Picker choice: `Default for this screen (W×H)`. | `GuestDisplay.swift`, `Library.swift`, `GameRecommendationsApply.swift`, `ContentView.swift` |
| P4 | The game layer (`refreshDisplayMode`) and the touch-controls window (`TouchControlsHost.attach`) re-frame on `DisplayGeometry.changed` as well as on orientation changes, so a fold that stays in landscape re-frames. Host check: guest 1336x936 through inner, outer, portrait and back in every display mode. | `ContentView.swift`, `DisplayGeometry.swift` |
| P5 | Library levels checked at six Duo widths. Idiom branches, pointer and portrait UI wait for round 1. | `check-library-zoom.py` |

## Decisions that differ from PLAN.md

- **Tokens only on a device that has shown two shapes.** PLAN.md gave every new entry the token. Storing it only after a second screen shape is seen keeps existing iPhones and iPads byte-for-byte unchanged (stored data as well as behaviour); the one-time pass catches entries made before the first fold.
- **"Same shape" uses `fills`' 1.5%.** Rotation, Display Zoom and More Space never count as a second shape. The 11-inch iPad and the Duo's inner screen are within 1.5% of each other, so they are one shape; a 1.4:1 outer screen is just outside it (1.55%) and counts as a second shape, each screen then getting its own default.
- **Settle delay unchanged** (one re-apply at 0.3 s). Revisit if round 1's log shows the fold animation running longer.

## Device round 1: what to capture

The `[display-geometry]` lines in `madeira-log.txt` answer the open questions: `screens=` (one screen object or two), `size-class=`, `idiom=`, the outer screen's `screen=`/`native=` sizes, and whether a fold logs `geometry` (same scene) or `disconnect` + `connect` (scene relaunch, the larger P4 risk). Follow the checklist in PLAN.md P1, then put the measured sizes into `DUO_SCREENS` in `check-duo-display.py` and the Duo rows of `check-control-presets.py` and `check-library-zoom.py`.

Round 1 can be built from this branch: the P2 to P4 changes only act when the screen changes shape, so they add to what round 1 shows rather than hide it.

## CI

`runs-on: xcode-27` is GitHub's hosted Xcode 27 image (generally available since October 2026), so the fork needs no runner override. Fork Actions are enabled, but no workflow has run on it yet: enable workflows in the fork's Actions tab, then start the first (several hours) run on `main`.
