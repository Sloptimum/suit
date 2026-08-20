import Cocoa

// The translucent ground under the window's sidebar world — the activity bar
// and the sidebar panel each keep one of these as their rearmost subview in
// place of the flat `barChrome` layer they used to bake in.
//
// Two layers make the look. The NSVisualEffectView (material .sidebar, blending
// .behindWindow) is the native frost: it samples the desktop behind the window,
// which is what makes the app read as a first-party Mac citizen instead of a
// painted rectangle. Over it sits a plain tint of `Theme.chromeTint` — the
// palette's own barChrome at partial alpha — so every theme keeps its hue
// identity on top of the blur; without the wash all fourteen palettes would
// share one system-grey sidebar. The two views are siblings here rather than
// pushed into each host so both hosts stay one line each and re-theme through
// one place.
//
// The effect view carries its *own* appearance, derived from the palette's
// lightness. The app pins .darkAqua app-wide (AppDelegate), which is right for
// menus and alerts, but a light palette over a dark-vibrant material would
// frost the sidebar dark under light chrome — the one place the global pin has
// to be overridden per theme.
//
// Behind-window blending was once deliberately stripped from this app (see
// FileBrowserView, where the source-list style's implicit effect view punched
// a desktop-shaped hole through the flat sidebar). The failure there was one
// transparent island in an opaque world; the redesign makes the whole left
// world translucent, so the file tree's clear ground now composites onto this
// backdrop by design.
//
// Offscreen renders (design/reference, cacheDisplay) can't sample a desktop, so
// the material falls back to its flat tint there — the committed reference PNG
// shows the wash over that fallback, slightly flatter than the live window.
final class ChromeBackdropView: NSView {
    private let effect = NSVisualEffectView(frame: .zero)
    private let tint = NSView(frame: .zero)

    // Nonzero when the backdrop grounds a floating card (the sidebar) instead
    // of a flush strip (the activity bar). An ancestor's masksToBounds is not
    // enough for behind-window material — the window server shapes the blur
    // region from the effect view itself, so a square backdrop under a rounded
    // card leaks frost past the corners. maskImage is the supported hook: a
    // stretchable rounded-rect template whose cap insets keep the corners
    // unscaled at any size. The mask's corners are circular while the card's
    // clip is a continuous curve; the divergence is sub-pixel at 10pt, and
    // where they differ the translucent tint composites over the well instead
    // of over blur — invisible in practice.
    var cornerRadius: CGFloat = 0 {
        didSet {
            guard cornerRadius != oldValue else { return }
            applyShape()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        effect.material = .sidebar
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        addSubview(effect)
        tint.wantsLayer = true
        addSubview(tint)
        applyTheme()
        applyShape()
        layoutParts()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutParts()
    }

    // Live theme switch: the tint color and the material's appearance are both
    // set-once state, so the hosts forward their reapplyTheme() here.
    func reapplyTheme() {
        applyTheme()
    }

    private func applyTheme() {
        effect.appearance = NSAppearance(named: Theme.current.isLight ? .vibrantLight : .vibrantDark)
        tint.layer?.backgroundColor = Theme.chromeTint.cgColor
    }

    private func applyShape() {
        if cornerRadius > 0 {
            let radius = cornerRadius
            // Minimal stretchable canvas: one pixel of straight edge between
            // the four unscaled corners.
            let side = radius * 2 + 1
            let mask = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
                NSColor.black.setFill()
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
                return true
            }
            mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
            mask.resizingMode = .stretch
            effect.maskImage = mask
            tint.layer?.cornerRadius = radius
            tint.layer?.cornerCurve = .continuous
        } else {
            effect.maskImage = nil
            tint.layer?.cornerRadius = 0
        }
    }

    private func layoutParts() {
        effect.frame = bounds
        tint.frame = bounds
    }
}
