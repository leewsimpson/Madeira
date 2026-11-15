// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright 2026 Lee Simpson
// Madeira Converter Exception: see LICENSE-EXCEPTION.md

import Foundation
#if canImport(UIKit)
import UIKit
#endif

// [display-geometry]: the screen as Madeira sees it, logged at launch and on
// every scene geometry or size-class change. The `[device]` line at launch
// (EntitlementChecker.swift) says nothing about a screen that changes while
// the app runs: a foldable (iPhone Duo) folds and unfolds, Stage Manager
// resizes. A line is written only when the reading differs from the scene's
// last one, so repeated callbacks for the same layout stay out of the log.

/// One reading of a scene's display. Foundation-only so the host checks can
/// build it (tests/host/check-duo-display.py).
struct DisplayGeometry: Equatable {
    /// Posted on the main queue when the app's own scene has a new reading. A
    /// fold that stays in landscape changes the scene's size without an
    /// orientation change, so the game layer and the touch controls re-frame
    /// on this as well as on UIDevice.orientationDidChangeNotification.
    static let changed = Notification.Name("MadeiraDisplayGeometryChanged")

    struct Insets: Equatable { var top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0 }

    /// The scene in points, as laid out now (Stage Manager or Split View can make it smaller than the screen).
    var scene: CGSize
    /// The scene's UIScreen in points, and UIScreen.nativeBounds in pixels (portrait-up).
    var screen: CGSize
    var native: CGSize
    var scale: CGFloat
    var nativeScale: CGFloat
    var orientation: String
    var horizontal: String
    var vertical: String
    var idiom: String
    var safeArea: Insets
    var screens: Int
    var maxFPS: Int

    private static func size(_ s: CGSize) -> String { "\(Self.number(s.width))x\(Self.number(s.height))" }
    private static func number(_ v: CGFloat) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", Double(v))
    }

    /// The log line's fields, without the `[display-geometry] <reason>` prefix.
    var line: String {
        let i = safeArea
        return "scene=\(Self.size(scene))pt screen=\(Self.size(screen))pt native=\(Self.size(native))px"
            + " scale=\(Self.number(scale)) native-scale=\(String(format: "%.3f", Double(nativeScale)))"
            + " orientation=\(orientation) size-class=\(horizontal)/\(vertical) idiom=\(idiom)"
            + " safe-area=\(Self.number(i.top)),\(Self.number(i.left)),\(Self.number(i.bottom)),\(Self.number(i.right))"
            + " screens=\(screens) max-fps=\(maxFPS)"
    }
}

#if canImport(UIKit)
extension DisplayGeometry {
    @MainActor init(_ scene: UIWindowScene) {
        let screen = scene.screen
        let window = scene.keyWindow ?? scene.windows.first
        let insets = window?.safeAreaInsets ?? .zero
        self.init(scene: scene.coordinateSpace.bounds.size,
                  screen: screen.bounds.size,
                  native: screen.nativeBounds.size,
                  scale: screen.scale,
                  nativeScale: screen.nativeScale,
                  orientation: Self.name(scene.effectiveGeometry.interfaceOrientation),
                  horizontal: Self.name(scene.traitCollection.horizontalSizeClass),
                  vertical: Self.name(scene.traitCollection.verticalSizeClass),
                  idiom: Self.name(scene.traitCollection.userInterfaceIdiom),
                  safeArea: Insets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right),
                  screens: UIScreen.screens.count,
                  maxFPS: screen.maximumFramesPerSecond)
    }

    static func name(_ o: UIInterfaceOrientation) -> String {
        switch o {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portrait-upside-down"
        case .landscapeLeft: return "landscape-left"
        case .landscapeRight: return "landscape-right"
        case .unknown: return "unknown"
        @unknown default: return "other(\(o.rawValue))"
        }
    }

    static func name(_ c: UIUserInterfaceSizeClass) -> String {
        switch c {
        case .compact: return "compact"
        case .regular: return "regular"
        case .unspecified: return "unspecified"
        @unknown default: return "other(\(c.rawValue))"
        }
    }

    static func name(_ i: UIUserInterfaceIdiom) -> String {
        switch i {
        case .phone: return "phone"
        case .pad: return "pad"
        case .mac: return "mac"
        case .tv: return "tv"
        case .carPlay: return "carplay"
        case .unspecified: return "unspecified"
        default: return "other(\(i.rawValue))"
        }
    }
}

/// Watches every window scene's effective geometry (KVO) and size classes
/// (trait registration) and writes a `[display-geometry]` line when either
/// changes. Started from MadeiraApp.init, before any scene connects.
@MainActor final class DisplayGeometryMonitor {
    static let shared = DisplayGeometryMonitor()

    private struct Watch {
        let geometry: NSKeyValueObservation
        let traits: UITraitChangeRegistration
    }
    private var watches: [ObjectIdentifier: Watch] = [:]
    private var last: [ObjectIdentifier: DisplayGeometry] = [:]
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        TouchRouteLog.start()   // [touch-route] diagnostics (device round 1b)
        let center = NotificationCenter.default
        center.addObserver(forName: UIScene.willConnectNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                if let scene = note.object as? UIWindowScene { DisplayGeometryMonitor.shared.watch(scene, reason: "connect") }
            }
        }
        center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                if let scene = note.object as? UIWindowScene { DisplayGeometryMonitor.shared.report(scene, reason: "activate") }
            }
        }
        center.addObserver(forName: UIScene.didDisconnectNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                guard let scene = note.object as? UIScene else { return }
                LogStore.shared.log("[display-geometry] disconnect scenes=\(UIApplication.shared.connectedScenes.count)")
                let id = ObjectIdentifier(scene)
                DisplayGeometryMonitor.shared.watches[id] = nil
                DisplayGeometryMonitor.shared.last[id] = nil
            }
        }
        for name in [UIScreen.didConnectNotification, UIScreen.didDisconnectNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated {
                    let what = note.name == UIScreen.didConnectNotification ? "screen-connect" : "screen-disconnect"
                    LogStore.shared.log("[display-geometry] \(what) screens=\(UIScreen.screens.count)")
                }
            }
        }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            watch(scene, reason: "launch")
        }
    }

    private func watch(_ scene: UIWindowScene, reason: String) {
        let id = ObjectIdentifier(scene)
        guard watches[id] == nil else { return }
        // UIKit changes effectiveGeometry on the main thread; the window's safe
        // area follows in the same layout pass, so the line is read just after.
        let geometry = scene.observe(\.effectiveGeometry, options: [.new]) { scene, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { DisplayGeometryMonitor.shared.report(scene, reason: "geometry") }
            }
        }
        let traits = scene.registerForTraitChanges([UITraitHorizontalSizeClass.self, UITraitVerticalSizeClass.self]) {
            (scene: UIWindowScene, _: UITraitCollection) in
            MainActor.assumeIsolated { DisplayGeometryMonitor.shared.report(scene, reason: "traits") }
        }
        watches[id] = Watch(geometry: geometry, traits: traits)
        for w in scene.windows { TouchRouteLog.attach(w) }
        report(scene, reason: reason)
    }

    func report(_ scene: UIWindowScene, reason: String) {
        let id = ObjectIdentifier(scene)
        if watches[id] == nil { watch(scene, reason: reason); return }
        let now = DisplayGeometry(scene)
        guard last[id] != now else { return }
        last[id] = now
        LogStore.shared.log("[display-geometry] \(reason) \(now.line)")
        // The app's own screen (not an external display's scene) sets the
        // Resolution choices: a foldable's fold changes them, a rotation does not.
        guard scene.session.role == .windowApplication else { return }
        NotificationCenter.default.post(name: DisplayGeometry.changed, object: scene)
        if ResolutionChoices.update(.landscape(points: now.screen, pixels: now.native)) {
            let d = ResolutionChoices.defaultSize()
            LogStore.shared.log("[display-geometry] resolution choices follow the screen: default \(d.w)x\(d.h)"
                + (ResolutionChoices.screen720Value.map { " 720-lines \($0)" } ?? ""))
        }
    }
}
#endif

#if canImport(UIKit)
// MARK: - [touch-route]: where each tap goes (madeira-duo device round 1b)
//
// Diagnostics for the device rounds, not for upstream. Built with the iOS 27
// SDK, the app runs natively on the iPhone Duo (an iOS 26.5 SDK build runs
// letterboxed), and there the library's toolbar and tab bar buttons highlight
// but do nothing. For the first taps of each run these lines say which window
// and view a touch landed on, whether it ended or was cancelled, the gesture
// recognizers that saw it and their states, and what was presented just
// after; every window shown or hidden is listed too.

/// Sees every touch that begins in its window. Never recognises, delays or
/// cancels one (the pattern of HardwareInput's TouchFocusObserver).
final class TouchRouteObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for t in touches { TouchRouteLog.began(t) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        for t in touches { TouchRouteLog.finished(t, how: "ended") }
        finishIfIdle(event)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        for t in touches { TouchRouteLog.finished(t, how: "CANCELLED") }
        finishIfIdle(event)
    }
    /// Fail once every touch of the sequence is over, so UIKit resets it.
    private func finishIfIdle(_ event: UIEvent) {
        let live = (event.allTouches ?? []).contains { $0.phase != .ended && $0.phase != .cancelled }
        if !live { state = .failed }
    }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool { false }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool { false }
}

@MainActor enum TouchRouteLog {
    /// Touches and window lines logged per run, so the log stays readable.
    static let touchLimit = 60
    static let windowLimit = 120
    private static var touches = 0
    private static var windowLines = 0
    private static var ids: [ObjectIdentifier: Int] = [:]
    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        center.addObserver(forName: UIWindow.didBecomeVisibleNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                guard let w = note.object as? UIWindow else { return }
                TouchRouteLog.window(w, "visible")
                TouchRouteLog.attach(w)
            }
        }
        center.addObserver(forName: UIWindow.didBecomeHiddenNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                if let w = note.object as? UIWindow { TouchRouteLog.window(w, "hidden") }
            }
        }
    }

    /// Watches a window's touches; the system keyboard's windows are left alone.
    static func attach(_ w: UIWindow) {
        let name = String(describing: type(of: w))
        guard !name.contains("Keyboard"), !name.contains("TextEffects") else { return }
        guard !(w.gestureRecognizers ?? []).contains(where: { $0 is TouchRouteObserver }) else { return }
        w.addGestureRecognizer(TouchRouteObserver())
    }

    static func window(_ w: UIWindow, _ what: String) {
        guard windowLines < windowLimit else { return }
        windowLines += 1
        LogStore.shared.log("[touch-route] window \(what) \(describe(w))")
    }

    /// Every window of every scene, top first.
    static func inventory(_ reason: String) {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        for w in windows.sorted(by: { $0.windowLevel.rawValue > $1.windowLevel.rawValue }) { window(w, "list(\(reason))") }
    }

    static func describe(_ w: UIWindow) -> String {
        let root = w.rootViewController.map { String(describing: type(of: $0)) } ?? "-"
        return "\(type(of: w)) level=\(Int(w.windowLevel.rawValue)) frame=\(rect(w.frame)) hidden=\(w.isHidden ? 1 : 0)"
            + " key=\(w.isKeyWindow ? 1 : 0) alpha=\(String(format: "%.2f", Double(w.alpha)))"
            + " touch=\(w.isUserInteractionEnabled ? 1 : 0) scene-screen=\(rect(w.windowScene?.screen.bounds ?? .zero))"
            + " root=\(root)"
    }

    static func rect(_ r: CGRect) -> String {
        String(format: "(%.0f,%.0f %.0fx%.0f)", Double(r.minX), Double(r.minY), Double(r.width), Double(r.height))
    }

    /// The touched view and its first ancestors, innermost first.
    static func chain(_ v: UIView?) -> String {
        var names: [String] = []
        var current = v
        while let c = current, names.count < 8 {
            names.append(String(describing: type(of: c)))
            current = c.superview
        }
        return names.isEmpty ? "-" : names.joined(separator: " < ")
    }

    static func recognizers(_ t: UITouch) -> String {
        let list = (t.gestureRecognizers ?? []).filter { !($0 is TouchRouteObserver) }
            .map { "\(type(of: $0)):\(name($0.state))" + ($0.isEnabled ? "" : "(off)") }
        return list.isEmpty ? "-" : list.joined(separator: ",")
    }

    static func name(_ s: UIGestureRecognizer.State) -> String {
        switch s {
        case .possible: return "possible"
        case .began: return "began"
        case .changed: return "changed"
        case .ended: return "ended"
        case .cancelled: return "cancelled"
        case .failed: return "failed"
        @unknown default: return "other"
        }
    }

    static func began(_ t: UITouch) {
        guard touches < touchLimit else { return }
        touches += 1
        let n = touches
        ids[ObjectIdentifier(t)] = n
        let p = t.location(in: t.window)
        let win = t.window.map { "\(type(of: $0)) level=\(Int($0.windowLevel.rawValue))" } ?? "-"
        LogStore.shared.log(String(format: "[touch-route] #%d began at (%.0f,%.0f)", n, Double(p.x), Double(p.y))
            + " window=\(win) type=\(t.type.rawValue) view=\(chain(t.view))")
        // Round 1c: the Duo draws the status bar, the toolbar's buttons and the tab
        // bar in a column on the right (the safe area's right inset), and taps there
        // reach only the root hosting view. Dump what is under such a tap.
        if let w = t.window, p.x >= w.bounds.width - max(w.safeAreaInsets.right, 1), dumps < dumpLimit {
            dumps += 1
            dump(w, at: p, tag: "#\(n)")
        }
    }

    private static var dumps = 0
    static let dumpLimit = 6

    /// Every view in the window whose frame holds the point, whether or not its
    /// parent's does (a view outside its parent's bounds is drawn but never hit),
    /// with its frame, flags and what its own hitTest returns there.
    static func dump(_ w: UIWindow, at p: CGPoint, tag: String) {
        var lines: [String] = []
        func short(_ v: AnyObject) -> String {
            let s = String(describing: type(of: v))
            return s.count > 90 ? String(s.prefix(90)) + "…" : s
        }
        func walk(_ v: UIView, depth: Int, parentHolds: Bool) {
            guard lines.count < 80 else { return }
            let frame = v.convert(v.bounds, to: w)
            let holds = frame.contains(p)
            if holds, !parentHolds, let parent = v.superview {
                // The view that stops the tap: the parent that does not reach the point.
                lines.append("\(depth - 1) PARENT \(short(parent)) frame=\(rect(parent.convert(parent.bounds, to: w)))"
                    + " touch=\(parent.isUserInteractionEnabled ? 1 : 0) clips=\(parent.clipsToBounds ? 1 : 0)")
            }
            if holds {
                let local = v.convert(p, from: w)
                let hit = v.hitTest(local, with: nil).map(short) ?? "nil"
                lines.append("\(depth) \(short(v)) frame=\(rect(frame))"
                    + " hidden=\(v.isHidden ? 1 : 0) alpha=\(String(format: "%.2f", Double(v.alpha)))"
                    + " touch=\(v.isUserInteractionEnabled ? 1 : 0) clips=\(v.clipsToBounds ? 1 : 0)"
                    + (parentHolds ? "" : " OUTSIDE-PARENT")
                    + " gestures=\(v.gestureRecognizers?.count ?? 0) hit=\(hit)")
            }
            for s in v.subviews { walk(s, depth: depth + 1, parentHolds: holds) }
        }
        walk(w, depth: 0, parentHolds: true)
        LogStore.shared.log("[touch-route] \(tag) dump at " + String(format: "(%.0f,%.0f)", Double(p.x), Double(p.y))
            + " window-safe-area=\(Int(w.safeAreaInsets.top)),\(Int(w.safeAreaInsets.left)),\(Int(w.safeAreaInsets.bottom)),\(Int(w.safeAreaInsets.right))"
            + " views=\(lines.count)")
        for l in lines { LogStore.shared.log("[touch-route] \(tag) | \(l)") }
    }

    static func finished(_ t: UITouch, how: String) {
        guard let n = ids.removeValue(forKey: ObjectIdentifier(t)) else { return }
        let p = t.location(in: t.window)
        LogStore.shared.log(String(format: "[touch-route] #%d ", n) + how
            + String(format: " at (%.0f,%.0f)", Double(p.x), Double(p.y))
            + " view=\(chain(t.view)) recognizers=\(recognizers(t))")
        // What the tap led to: a menu, sheet or tab change shows up here.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            MainActor.assumeIsolated {
                LogStore.shared.log("[touch-route] #\(n) after: presented=\(TouchRouteLog.presented())")
                if n <= 3 || how != "ended" { TouchRouteLog.inventory("#\(n)") }
            }
        }
    }

    /// The view controllers presented over each window's root, outermost last.
    static func presented() -> String {
        var out: [String] = []
        for w in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows) {
            var vc = w.rootViewController?.presentedViewController
            while let p = vc {
                out.append(String(describing: type(of: p)))
                vc = p.presentedViewController
            }
        }
        return out.isEmpty ? "none" : out.joined(separator: ",")
    }
}
#endif
