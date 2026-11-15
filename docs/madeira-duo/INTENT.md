# Madeira: iPhone Duo Compatibility

Nov 15, 2026 · Lee Simpson

## Goal

Make [Madeira](https://github.com/willfaust/Madeira), the app that runs Windows PC games on a jailed iPhone, work fully on the iPhone Duo: correct layout, resolution and input on both the 7.6" inner screen (about 1.4:1) and the 5.4" outer screen, including folding and unfolding while the app or a game is running. The result is a patch or PR that can be built and sideloaded.

Success criteria:

- The library, settings and Steam screens lay out correctly on both screens, in every supported orientation.
- A game launched on either screen gets a sensible default resolution and fills the screen without black bars or stretching.
- Touch controls, mouse and pointer input map to the right place in the game image.
- Folding or unfolding mid-game does not crash, freeze or leave the picture mis-sized.
- Nothing regresses on existing iPhones and iPads.

## Target device

The iPhone Duo is Apple's first foldable, announced 2026-09-09. Its inner screen is about 7.6" at roughly 1.4:1 and wider than tall when open; the outer screen is about 5.4".

| Item | Value | Source |
| --- | --- | --- |
| Inner display | about 7.6", about 1.4:1, roughly 2670 x 1878 px (database listing) | [Wikipedia](https://en.wikipedia.org/wiki/IPhone_Duo), [9to5Mac](https://9to5mac.com/2026/10/21/iphone-duo-review/) |
| Outer display | 5.4" (one source says 6.3") | [TechCrunch](https://techcrunch.com/2026/09/09/apple-unveils-its-first-foldable-the-iphone-duo/) |
| Aspect ratio | 1.4:1 on both screens per Consumer Reports; other sources say inner only | [Consumer Reports](https://www.consumerreports.org/electronics-computers/cell-phones/apple-iphone-duo-review-a5520585020/) |

Open questions to settle on the real device: the outer screen's exact size and ratio, RAM, whether iOS reports one screen or two, and how size classes change on fold.

Madeira already ships to iPad (`TARGETED_DEVICE_FAMILY` is 1,2), so much of the Duo's inner-screen shape is covered. Based on a read of `app/Madeira` at commit fbad4304; nothing has been built or run yet.

Already in place:

- `ResolutionChoices` in `GuestDisplay.swift` builds default resolutions from the screen's points and pixels, so a 1.4:1 screen gets screen-shaped choices instead of the 19.5:9 default.
- Display modes Fit, Fill, Stretch and Aspect, with shared rect and input-mapping code (`GameSurfaceLayout.rect/map`).
- iPad-specific layout and keyboard handling in `ContentView.swift`.
- Emulation (FEX), Wine, JIT and Metal rendering do not depend on the form factor.

Likely to break:

- `ResolutionChoices.screen` is a `static var` read once at launch, so it goes stale when the Duo folds or unfolds.
- The guest resolution is chosen when a game starts. A mid-game fold changes the drawable, but Wine and the game keep their old mode.
- Touch-control presets (`TouchControlPresets.swift`) were designed for phone and iPad shapes.
- Size-class and orientation logic in `ContentView.swift` assumes iPad is regular in both orientations. The Duo's classes are unknown.
- `PhonePointer.m` forces the iPad idiom with private APIs and needs checking on the Duo.

## Constraints

**Work happens on a Windows PC.** Almost all development and checking has to be possible there. The full app cannot be built or run on Windows, because it needs Xcode and macOS, so anything that depends on the real app is verified through an online build and the real Duo.

**The development cycle must stay fast.** The loop that runs on the PC (edit, compile, test the layout and resolution logic against Duo geometry) is the main loop and should take seconds to minutes. The slow loop (online build, sideload, test on the Duo) is used only for what the PC cannot show, and is kept to as few rounds as possible.

**Tools and cost.** Prefer free services for building the IPA. A real iPhone Duo is available for testing.

**Scope.** Changes stay small and contained, ideally in the app layer, so they can be proposed upstream. Existing iPhone and iPad behaviour must not change, and the project's GPL-3.0 licence applies.
