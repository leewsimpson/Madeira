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

`runs-on: xcode-27` is GitHub's hosted Xcode 27 image (generally available since October 2026), so the fork needs no runner override. The first fork run (`main`, 2026-11-15) took 66 minutes; with its caches a branch build takes about 10. The first branch build failed on one compile error (`effectiveGeometry.coordinateSpace` needs iOS 26), fixed in 3d5cc589.

## Device round 1 (2026-11-15): results

From `[display-geometry]` on an iPhone19,4, iOS 27.2.1:

- Outer screen: 466x678 pt portrait, 1398x2034 px @3x, `compact/regular`, idiom `phone`, one UIScreen. Default resolution 1152x792.
- Inner screen: 951x669 pt, held normally it reads `landscape-left`; 1878x2670 px, scale 3, native scale 2.807; `regular/regular` with idiom `phone` (no iPhone did that before); `UIScreen.screens` is 2 while unfolded. Default resolution 1152x808.
- A fold is a `geometry` change of the same scene plus `screen-connect`/`screen-disconnect`; no scene disconnect, so the app is not relaunched and P4 stays small.
- No reading storm: lines only at folds.

The library's toolbar (filter menu, +) and tab bar (Settings) highlight but do nothing, on both screens. Not the Duo commit: the fork's `main` build does the same. The official 0.2.0 IPA works because it was built with Xcode 26.5 / iOS 26.5 SDK (DTSDKName iphoneos26.5), so iOS runs it letterboxed in a compatibility window; every fork build uses Xcode 27.1 / iOS 27.1 SDK and runs natively. Unknown yet whether an ordinary iPhone on iOS 27 shows the same with an SDK 27 build. Overlay windows (PassthroughWindow, ControlsWindow, LibraryKeyboardWindow) and the window-level touch observers (TouchFocusObserver, WindowTouchObserver) all pass touches through.

Round 1b adds `[touch-route]` diagnostics (DisplayGeometry.swift; remove before upstream): each window shown or hidden, the first 60 touches with their window, view chain, ended or CANCELLED, the gesture recognizers' states, and what was presented 0.6 s later; `library + tapped` and `library tab a -> b` when those actions run.

## Device rounds 1c–3 (2026-11-15): dead library buttons fixed

- **Symptom:** built with the iOS 27 SDK (native on the Duo), the library's toolbar
  buttons (filter, +) and tab bar (library, Settings) highlighted but did nothing.
  iOS puts the status bar, toolbar and tab bar in a column inside the 84 pt right
  safe-area inset.
- **Round 1c** (`77f2aaf1`): the view dump showed the NavigationStack host covering
  the full 951x669 window and hit-testing to the buttons correctly, but sitting
  outside its parent's bounds. Taps stopped at the root `_UIHostingView`.
- **Round 2** (`3eaf4461`): `.ignoresSafeArea()` on `ContentView()`, applied *inside*
  the root modifiers. Didn't help. The new `PARENT` line named the blocker:
  `_UIInteractionView<GCEventInteraction…>` at 867x635, the wrapper that
  `.handlesGameControllerEvents` (`ClaimGamepadEvents`) adds, sized to the safe area.
- **Round 3** (`ce0225f8`): `.ignoresSafeArea()` moved *outside*
  `.modifier(ClaimGamepadEvents())` in `MadeiraApp.swift`. The same build adds a
  `BarTapCheck` self-check plus a UIWindow hitTest "rescue" that turns on only if the
  self-check fails. **Buttons work on the Duo (user confirmed).**
- **Round 3 log (22:12):** the rescue never fired (no `rescue at` lines), yet tab
  switches and toolbar taps worked, so the `.ignoresSafeArea()` move alone is the fix.
  The self-check's 2 FAILs were false alarms: at each tab button's centre the hit test
  returned a *different* `_UITabButton` instance (a second copy of the tab bar), and the
  check compared object identity. The `duo-round 3` line repeats because it is logged
  from ContentView's `onAppear`, which re-runs; those aren't relaunches.
- **Open:** remove the diagnostics before upstream
  (`[touch-route]`, `BarTapCheck` with its swizzle, the `duo-round` line, the two
  `Library.swift` log lines). Check that regular iPhone and iPad layouts are
  unchanged, and update `DUO_SCREENS` with the round 1 measurements.
- **Builds:** IPAs go in `C:\Github\Madeira\builds\` (git-ignored), numbered, with
  the newest marked `-INSTALL-THIS`.
