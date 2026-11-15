# Madeira on iPhone Duo: Plan

Nov 15, 2026 · Lee Simpson · goes with [INTENT.md](INTENT.md)

Based on `app/Madeira` at fbad4304. Nothing has been built or run on a device yet.

## Approach

Most of the work is display geometry, and that code is already split so it can be tested without UIKit. Each change is tested on the PC first, against Duo screen fixtures and against fixtures for current iPhones and iPads. Builds on the phone are used for two things only: measuring the Duo, then confirming the fixes. The plan expects **three device rounds**.

## What the code already does (beyond INTENT.md)

| Area | Today | Effect on the Duo |
| --- | --- | --- |
| Default resolution | `LibraryEntry.resolution = ResolutionChoices.defaultValue` is **stored on the entry when it is created** ([Library.swift:195](../../app/Madeira/Library.swift)). `configureSessionDefault` gets a fixed 1280x720 view and uses the stored value ([Library.swift:864](../../app/Madeira/Library.swift), [:899](../../app/Madeira/Library.swift)). | A game added on one screen keeps that screen's shape on the other. This matters more than `screen` being stale. |
| Screen model | `ResolutionChoices.screen` is a lazy `static var` read from `UIScreen.main` in `MadeiraApp.init` ([GuestDisplay.swift:183](../../app/Madeira/GuestDisplay.swift)). | The picker, default and `screen720` stay on the screen the app was launched on. |
| Game layer | `MetalBackedView.layoutSubviews` and the orientation observer re-run `GameSurfaceLayout.rect` and the compositor frame; touch input uses the same rect ([ContentView.swift:249-336](../../app/Madeira/ContentView.swift)). | A mid-game fold already re-letterboxes the picture and remaps touch. The guest mode stays the same, so you get bars (Fit/Aspect), cropping (Fill) or distortion (Stretch). |
| Rotation settle | One re-apply 0.3 s after the change ([ContentView.swift:270](../../app/Madeira/ContentView.swift)). | A fold animation may take longer than 0.3 s. Check on the device. |
| Orientation | The developer UI picks portrait or landscape from its own shape, not from size classes ([ContentView.swift:1407](../../app/Madeira/ContentView.swift)). The iPhone allows portrait and both landscapes ([Info.plist](../../app/Madeira/Info.plist)). | The inner screen is about 1.4:1 when held in portrait, so the portrait UI has to work on a nearly square screen. |
| Idiom checks | `HardwareInput` turns off pointer lock and turns on the AssistiveTouch hint on `.phone`. `PhonePointer.m` changes nothing unless `MADEIRA_PHONE_*` is set. The Steam sign-in default and copy also depend on the idiom. | Behaviour depends on which idiom the Duo reports. Measure it in round 1. |
| Touch controls | Positions are normalised (`nx`, `ny`) and laid out per screen by `ControlPresetLayout`. | They scale already. They need Duo fixtures in the host check. |
| Startup log | `[device] … screen=WxH@scale` is logged once at launch ([EntitlementChecker.swift:169](../../app/Madeira/EntitlementChecker.swift)). | Gives no information about folding. |

## Fast loop on Windows (checked today)

Swift 6.4.2 is installed. The existing host checks compile production Swift on Windows once `SDKROOT` is set:

```bash
export SDKROOT="$(cygpath -w "$LOCALAPPDATA/Programs/Swift/Platforms/6.4.2/Windows.platform/Developer/SDKs/Windows.sdk")"
```

| Check | Result on this PC |
| --- | --- |
| `check-control-presets.py` | 155 pass, 4 s |
| `check-pointer-geometry.py` | 3 pass, 4 s |
| `check-game-recommendations.py` | 8 pass, 6 s |
| `check-library-zoom.py`, `check-library-sections.py` | pass |
| `check-frontend.py` | Swift part runs. The C part fails because `cc` is not on PATH (fix: add a `CC` override, or install clang or LLVM-MinGW). |

The loop is: edit the Swift file, run the matching check, done in about 5 s. Nothing that goes upstream depends on Windows; the only addition is a `CC`/`SWIFTC` override.

## Phases

### P0. PC harness and Duo fixtures (PC)

1. Add `tools/host/env.ps1`, or a note in the checks, that sets `SDKROOT`, and add a `CC` override to `check-frontend.py`.
2. Add a new `tests/host/check-duo-display.py`. It compiles `GameSurfaceLayout`, `GuestDisplay` and `ResolutionChoices`, plus the new screen-model code from P2.
   - **Duo fixtures** (placeholders until round 1 measures them): inner screen at 2670x1878 px, as 1335x939 pt @2x or 890x626 pt @3x. Outer screen in two candidate shapes, about 19.5:9 and about 1.4:1.
   - **Golden fixtures for today's devices**: 6.1", 6.3" and 6.9" iPhones, iPad mini, 11" iPad and 13" iPad. Record what `groups`, `defaultSize`, `screen720` and `metalFX` return **before any change**, so a later change cannot move them.
3. Add the Duo screens to the `screens` list in `check-control-presets.py` and to `check-library-zoom.py`.

The goal is that every later PC change can be checked against both screens and against no regression on existing devices.

### P1. Device round 1: measure (slow loop)

The build is upstream main plus one low-risk addition: a `[display-geometry]` log line, written at launch and on **every** scene geometry or trait change. It records:

- window bounds in points, `nativeBounds`, scale and native scale
- interface orientation
- horizontal and vertical size classes and the idiom
- safe-area insets
- `UIScreen.screens.count`
- `maximumFramesPerSecond`

Hook it to `windowScene(_:didUpdate:…)` / `registerForTraitChanges`. It is upstreamable as diagnostics.

On the Duo, record the following with the app on the library screen, then again during a running game:

1. Launch on the outer screen and unfold. Launch on the inner screen and fold.
2. Rotate each screen through portrait and landscape.
3. Run one game (the Desktop entry and one D3D11 title) through fold and unfold. Note crashes, freezes and how the picture looks in Fit, Fill, Stretch and Aspect.
4. Note whether the app is killed or relaunched on fold (iOS may treat it as a scene reconnect).
5. Export the log.

Outcome: real fixture values replace the P0 placeholders, and the open questions in INTENT.md get answers: one screen object or two, the size classes, the idiom and the outer screen's ratio.

### P2. Screen model that follows the screen (PC)

- Replace the lazy `ResolutionChoices.screen` with a value that can be updated (`ResolutionChoices.update(from:)`). The scene geometry hook from P1 calls it and posts a change notification that the library observes. The UIKit read stays where it is, behind `#if canImport(UIKit)`. The pure math already takes `Screen` as a parameter.
- `MadeiraApp.init` keeps its first read, so start-up order is unchanged.
- Host check: Duo fixtures return screen-shaped groups for each screen, and golden fixtures are unchanged.

### P3. Default resolution chosen at launch (PC)

- Add a stored token for the default (e.g. `"screen"`). `LibraryEntry` gets it for new entries, and the launch path resolves it to `ResolutionChoices.defaultValue` **for the screen the game starts on** before `configureSessionDefault`. On devices with one fixed screen it resolves to exactly today's value, so they see no change.
- In the picker, the first choice reads `Default for this screen (WxH)`. A concrete size the user picks stays fixed, as it does today.
- Migration, modelled on the ml1172 reset ([Library.swift:1127](../../app/Madeira/Library.swift)): a one-time pass that runs only once the app has seen a second screen shape. It converts entries whose value equals the old default of a screen shape the app has seen to the token. Existing iPhones and iPads never meet that condition.
- `GameRecommendationsApply`'s `screen720Value` gets the same treatment: store a token and resolve it at launch.
- Host checks: the frontend check (launch environment per screen) and the new Duo check. Golden values for single-screen devices are unchanged.

### P4. Fold and unfold mid-game (PC, then device)

Minimum requirement (success criterion 4): no crash, no freeze, the picture correctly placed and touch input correct.

- The guest mode is not changed mid-game. The layer is laid out again for the new bounds. Fit and Aspect letterbox; Fill crops. Touch already follows the same rect.
- Re-apply on scene geometry change as well as the orientation notification, because a fold that stays in landscape may not post an orientation change. Increase the settle delay or add a second settle if round 1 shows the fold animation takes longer than 0.3 s.
- Touch controls: `TouchControlsHost.attach()` is called only when `landscape` flips. Also call it when the size changes, so the controls window re-frames on a landscape-to-landscape fold.
- Stretch across a big change in shape (1.4:1 to about 2.2:1) distorts badly. Proposal: leave it as is, since the user chose Stretch. Revisit only if the device test shows a problem.
- Host check: a fold sequence in `check-pointer-geometry` style (guest 1336x936, bounds go from inner to outer and back). It checks the rect and that touch corners map to guest corners after each step.
- **Out of scope for the first PR:** switching the guest's display mode live after a fold. Pushing a new mode into win32u mid-game needs Wine and game cooperation (`sysparams_ios.c`), and many games ignore it. Consider it later, behind a cfg switch, once letterboxing has been seen on the device.

### P5. App screens and input on both screens (PC, then device)

- Library grid: check the levels at Duo widths (`check-library-zoom`).
- Settings, library session and Steam sign-in: review for idiom-only branches. Keep the existing behaviour on existing devices, and branch on the measured idiom or size class only if round 1 needs it. The likely spots are `SteamSignInView` (QR on iPad) and the AssistiveTouch hint.
- Pointer: if the Duo reports `.phone` but iOS routes a mouse to it the way it does on iPad, `pointerLockAvailable` and `hoverSeen` need a capability check instead of an idiom check. Decide from round 1. Leave `PhonePointer.m` alone unless round 1 shows a problem with it.
- Portrait on the inner screen: the developer UI's portrait layout at about 939x1335 pt. These SwiftUI changes are confirmed on the device in round 2; the PC cannot render SwiftUI.

### P6. Device round 2: confirm the fixes (slow loop)

Run the round 1 checklist on the build with P2 to P5, plus:

- A game added on the outer screen launches screen-shaped on the inner screen, and the other way round.
- Fold and unfold 5 times mid-game in each display mode. Check that touch hits the corners and that the touch controls stay inside the safe area.
- The resolution picker shows the current screen after a fold.

If a second iPhone or iPad is available, run a short smoke test on it (launch, resolution default, one game). Round 3 is kept for fixes and the final build.

### P7. Upstream PR

The PR is small and limited to the app: `GuestDisplay.swift`, `Library.swift`, the scene geometry hook, the `TouchControlsHost` re-frame, the new host check and the extra fixtures. Golden values show existing devices are unchanged. Logs from the device rounds go in as evidence. GPL-3.0 headers follow the existing files.

## Slow loop: CI and sideload

- The CI workflow ([.github/workflows/build.yml](../../.github/workflows/build.yml)) runs on `runs-on: xcode-27`. Check that this runner label exists for the `leewsimpson/Madeira` fork. If it doesn't, override it to a GitHub-hosted macOS image; macOS runners are free on public repos.
- The **first run on the fork takes several hours** (LLVM twice, FEX, Wine). Start it right away on an unchanged `main`, so the native caches are warm before round 1. App-only changes after that reuse the seven runtime caches (BUILDING.md) and take minutes plus the Xcode build. Branches see caches from the fork's `main`.
- Sideload the `Madeira-ipa` artifact with SideStore or AltStore, then enable JIT with StikDebug as usual.

## Risks and open questions

- **Duo geometry is unknown** until round 1. The fixtures are placeholders, and P2 to P4 are designed so the measured numbers only need to go into the fixtures, not into the code.
- **iOS may relaunch the scene on fold.** If it does, the mid-game work turns into making sure a scene reconnect keeps the game session (the singleton `MetalHostView` re-parents already). That would be a larger change; decide after round 1.
- **The `xcode-27` runner might not be available on a fork.** In that case the slow loop needs an override to a GitHub-hosted macOS image, as described above.
- **Is a non-Duo test device available** for the regression smoke test? Otherwise the PC golden fixtures are the only regression guard.
