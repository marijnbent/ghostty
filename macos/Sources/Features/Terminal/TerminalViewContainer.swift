import AppKit
import SwiftUI

/// Use this container to achieve a glass effect at the window level.
/// Modifying `NSThemeFrame` can sometimes be unpredictable.
class TerminalViewContainer: NSView {
    private let terminalView: NSView
    private let sidebarView = NSHostingView(rootView: AnyView(EmptyView()))
    private let sidebarDivider = NSBox()
    private let sidebarResizeHandle = SidebarResizeHandleView()
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var sidebarLeadingConstraint: NSLayoutConstraint?
    private var terminalLeadingConstraint: NSLayoutConstraint?
    private let minSidebarWidth: CGFloat = 180
    private let maxSidebarWidth: CGFloat = 420

    /// Combined glass effect and inactive tint overlay view
    private(set) var glassEffectView: NSView?
    private var derivedConfig: DerivedConfig?
    var onSidebarWidthChanged: ((CGFloat) -> Void)?

    var windowThemeFrameView: NSView? {
        window?.contentView?.superview
    }

    var windowCornerRadius: CGFloat? {
        guard let window, window.responds(to: Selector(("_cornerRadius"))) else {
            return nil
        }

        return window.value(forKey: "_cornerRadius") as? CGFloat
    }

    init<Root: View>(@ViewBuilder rootView: () -> Root) {
        self.terminalView = NSHostingView(rootView: rootView())
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The initial content size to use as a fallback before the SwiftUI
    /// view hierarchy has completed layout (i.e. before @FocusedValue
    /// propagates `lastFocusedSurface`). Once the hosting view reports
    /// a valid intrinsic size, this fallback is no longer used.
    var initialContentSize: NSSize?

    override var intrinsicContentSize: NSSize {
        let hostingSize = terminalView.intrinsicContentSize
        // The hosting view returns a valid size once SwiftUI has laid out
        // with the correct idealWidth/idealHeight. Before that (when
        // @FocusedValue hasn't propagated), it returns a tiny default.
        // Fall back to initialContentSize in that case.
        if let initialContentSize,
           hostingSize.width < initialContentSize.width || hostingSize.height < initialContentSize.height {
            return initialContentSize
        }
        return hostingSize
    }

    private func setup() {
        sidebarView.translatesAutoresizingMaskIntoConstraints = false
        sidebarView.isHidden = true

        sidebarDivider.translatesAutoresizingMaskIntoConstraints = false
        sidebarDivider.boxType = .custom
        sidebarDivider.isTransparent = true
        sidebarDivider.fillColor = .separatorColor
        sidebarDivider.isHidden = true

        sidebarResizeHandle.translatesAutoresizingMaskIntoConstraints = false
        sidebarResizeHandle.isHidden = true
        sidebarResizeHandle.currentWidth = { [weak self] in
            self?.sidebarWidthConstraint?.constant ?? 240
        }
        sidebarResizeHandle.onResize = { [weak self] width in
            self?.setSidebarWidth(width, notify: true)
        }

        addSubview(sidebarView)
        addSubview(sidebarDivider)
        addSubview(sidebarResizeHandle)
        addSubview(terminalView)
        terminalView.translatesAutoresizingMaskIntoConstraints = false

        sidebarWidthConstraint = sidebarView.widthAnchor.constraint(equalToConstant: 240)
        sidebarLeadingConstraint = terminalView.leadingAnchor.constraint(equalTo: leadingAnchor)
        terminalLeadingConstraint = terminalView.leadingAnchor.constraint(equalTo: sidebarDivider.trailingAnchor)

        NSLayoutConstraint.activate([
            sidebarView.topAnchor.constraint(equalTo: topAnchor),
            sidebarView.leadingAnchor.constraint(equalTo: leadingAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: bottomAnchor),
            sidebarWidthConstraint!,

            sidebarDivider.topAnchor.constraint(equalTo: topAnchor),
            sidebarDivider.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            sidebarDivider.bottomAnchor.constraint(equalTo: bottomAnchor),
            sidebarDivider.widthAnchor.constraint(equalToConstant: 1),

            sidebarResizeHandle.topAnchor.constraint(equalTo: topAnchor),
            sidebarResizeHandle.centerXAnchor.constraint(equalTo: sidebarDivider.centerXAnchor),
            sidebarResizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor),
            sidebarResizeHandle.widthAnchor.constraint(equalToConstant: 12),

            terminalView.topAnchor.constraint(equalTo: topAnchor),
            sidebarLeadingConstraint!,
            terminalLeadingConstraint!,
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        terminalLeadingConstraint?.isActive = false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateGlassEffectIfNeeded()
        updateGlassEffectTopInsetIfNeeded()
    }

    override func layout() {
        super.layout()
        updateGlassEffectTopInsetIfNeeded()
    }

    func ghosttyConfigDidChange(_ config: Ghostty.Config, preferredBackgroundColor: NSColor?) {
        let newValue = DerivedConfig(config: config, preferredBackgroundColor: preferredBackgroundColor, cornerRadius: windowCornerRadius)
        guard newValue != derivedConfig else { return }
        derivedConfig = newValue
        DispatchQueue.main.async(execute: updateGlassEffectIfNeeded)
    }

    func updateWorkspaceSidebar(rootView: AnyView?, width: CGFloat = 240) {
        let hasSidebar = rootView != nil
        sidebarView.rootView = rootView ?? AnyView(EmptyView())
        sidebarView.isHidden = !hasSidebar
        sidebarDivider.isHidden = !hasSidebar
        sidebarResizeHandle.isHidden = !hasSidebar
        setSidebarWidth(hasSidebar ? width : 0, notify: false)
        sidebarLeadingConstraint?.isActive = !hasSidebar
        terminalLeadingConstraint?.isActive = hasSidebar
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func updateWorkspaceSidebarDividerColor(_ color: NSColor) {
        sidebarDivider.fillColor = color
    }

    private func setSidebarWidth(_ width: CGFloat, notify: Bool) {
        let clampedWidth = if width <= 0 {
            CGFloat.zero
        } else {
            min(max(width, minSidebarWidth), maxSidebarWidth)
        }

        sidebarWidthConstraint?.constant = clampedWidth

        if notify, clampedWidth > 0 {
            onSidebarWidthChanged?(clampedWidth)
        }
    }
}

private final class SidebarResizeHandleView: NSView {
    var onResize: ((CGFloat) -> Void)?
    var currentWidth: (() -> CGFloat)?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let initialLocation = event.locationInWindow.x
        let initialWidth = currentWidth?() ?? 240

        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: .greatestFiniteMagnitude,
            mode: .eventTracking
        ) { [weak self] trackedEvent, stop in
            guard let trackedEvent else {
                stop.pointee = true
                return
            }

            guard let self else {
                stop.pointee = true
                return
            }

            let delta = trackedEvent.locationInWindow.x - initialLocation
            onResize?(initialWidth + delta)

            if trackedEvent.type == .leftMouseUp {
                stop.pointee = true
            }
        }
    }
}

// MARK: - BaseTerminalController + terminalViewContainer

extension BaseTerminalController {
    var terminalViewContainer: TerminalViewContainer? {
        window?.contentView as? TerminalViewContainer
    }
}

// MARK: Glass

/// An `NSView` that contains a liquid glass background effect and
/// an inactive-window tint overlay.
#if compiler(>=6.2)
@available(macOS 26.0, *)
private class TerminalGlassView: NSView {
    private let glassEffectView: NSGlassEffectView
    private var topConstraint: NSLayoutConstraint!
    private let tintOverlay: NSView

    init(topOffset: CGFloat) {
        self.glassEffectView = NSGlassEffectView()
        self.tintOverlay = NSView()
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false

        // Glass effect view fills this view.
        glassEffectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassEffectView)
        topConstraint = glassEffectView.topAnchor.constraint(
            equalTo: topAnchor,
            constant: topOffset
        )
        NSLayoutConstraint.activate([
            topConstraint,
            glassEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            glassEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // Tint overlay sits above the glass effect.
        tintOverlay.translatesAutoresizingMaskIntoConstraints = false
        tintOverlay.wantsLayer = true
        tintOverlay.alphaValue = 0
        addSubview(tintOverlay, positioned: .above, relativeTo: glassEffectView)

        NSLayoutConstraint.activate([
            tintOverlay.topAnchor.constraint(equalTo: glassEffectView.topAnchor),
            tintOverlay.leadingAnchor.constraint(equalTo: glassEffectView.leadingAnchor),
            tintOverlay.bottomAnchor.constraint(equalTo: glassEffectView.bottomAnchor),
            tintOverlay.trailingAnchor.constraint(equalTo: glassEffectView.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Configures the glass effect style, tint color, corner radius, and
    /// updates the inactive tint overlay based on window key status.
    func configure(
        style: NSGlassEffectView.Style,
        backgroundColor: NSColor,
        backgroundOpacity: Double,
        cornerRadius: CGFloat?,
        isKeyWindow: Bool
    ) {
        glassEffectView.style = style
        glassEffectView.tintColor = backgroundColor.withAlphaComponent(backgroundOpacity)
        glassEffectView.cornerRadius = cornerRadius ?? 0
        updateKeyStatus(isKeyWindow, backgroundColor: backgroundColor)
    }

    /// Updates the top inset offset for both the glass effect and tint overlay.
    /// Call this when the safe area insets change (e.g., during layout).
    func updateTopInset(_ offset: CGFloat) {
        topConstraint.constant = offset
    }

    /// Updates the tint overlay visibility based on window key status.
    func updateKeyStatus(_ isKeyWindow: Bool, backgroundColor: NSColor) {
        let tint = tintProperties(for: backgroundColor)
        tintOverlay.layer?.backgroundColor = tint.color.cgColor
        tintOverlay.alphaValue = isKeyWindow ? 0 : tint.opacity
    }

    /// Computes a saturation-boosted tint color and opacity for the inactive overlay.
    private func tintProperties(for color: NSColor) -> (color: NSColor, opacity: CGFloat) {
        let isLight = color.isLightColor
        let vibrant = color.adjustingSaturation(by: 1.2)
        let overlayOpacity: CGFloat = isLight ? 0.35 : 0.85
        return (vibrant, overlayOpacity)
    }
}
#endif // compiler(>=6.2)

extension TerminalViewContainer {
#if compiler(>=6.2)
    @available(macOS 26.0, *)
    private func addGlassEffectViewIfNeeded() -> TerminalGlassView? {
        if let existed = glassEffectView as? TerminalGlassView {
            updateGlassEffectTopInsetIfNeeded()
            return existed
        }
        guard let themeFrameView = windowThemeFrameView else {
            return nil
        }
        let effectView = TerminalGlassView(topOffset: -themeFrameView.safeAreaInsets.top)
        addSubview(effectView, positioned: .below, relativeTo: terminalView)
        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        glassEffectView = effectView
        return effectView
    }
#endif // compiler(>=6.2)

    private func updateGlassEffectIfNeeded() {
#if compiler(>=6.2)
        guard #available(macOS 26.0, *), let derivedConfig else {
            glassEffectView?.removeFromSuperview()
            glassEffectView = nil
            return
        }
        guard let effectView = addGlassEffectViewIfNeeded() else {
            return
        }

        effectView.configure(
            style: derivedConfig.style.official,
            backgroundColor: derivedConfig.backgroundColor,
            backgroundOpacity: derivedConfig.backgroundOpacity,
            cornerRadius: derivedConfig.cornerRadius,
            isKeyWindow: window?.isKeyWindow ?? true
        )
#endif // compiler(>=6.2)
    }

    private func updateGlassEffectTopInsetIfNeeded() {
#if compiler(>=6.2)
        guard
            #available(macOS 26.0, *),
            let effectView = glassEffectView as? TerminalGlassView,
            let themeFrameView = windowThemeFrameView
        else {
            return
        }
        effectView.updateTopInset(-themeFrameView.safeAreaInsets.top)
#endif // compiler(>=6.2)
    }

    func updateGlassTintOverlay(isKeyWindow: Bool) {
#if compiler(>=6.2)
        guard
            #available(macOS 26.0, *),
            let effectView = glassEffectView as? TerminalGlassView,
            let derivedConfig
        else {
            return
        }
        effectView.updateKeyStatus(isKeyWindow, backgroundColor: derivedConfig.backgroundColor)
#endif // compiler(>=6.2)
    }

    struct DerivedConfig: Equatable {
        let style: BackportNSGlassStyle
        let backgroundColor: NSColor
        let backgroundOpacity: Double
        let cornerRadius: CGFloat?

        init?(config: Ghostty.Config, preferredBackgroundColor: NSColor?, cornerRadius: CGFloat?) {
            switch config.backgroundBlur {
            case .macosGlassRegular:
                style = .regular
            case .macosGlassClear:
                style = .clear
            default:
                return nil
            }
            self.backgroundColor = preferredBackgroundColor ?? NSColor(config.backgroundColor)
            self.backgroundOpacity = config.backgroundOpacity
            self.cornerRadius = cornerRadius
        }
    }
}
