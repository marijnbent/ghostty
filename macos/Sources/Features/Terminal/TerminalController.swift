import Foundation
import Cocoa
import SwiftUI
import Combine
import GhosttyKit

struct WorkspaceCloseSelectionEntry: Equatable {
    let id: String
    let isInactive: Bool
}

enum WorkspaceSelectionHistory {
    static func recordingSelection(_ history: [String], workspaceID: String) -> [String] {
        history.filter { $0 != workspaceID } + [workspaceID]
    }

    static func pruned(_ history: [String], validWorkspaceIDs: Set<String>) -> [String] {
        history.filter { validWorkspaceIDs.contains($0) }
    }
}

enum WorkspaceAutomaticTitleTracking {
    static func shouldTrackComputedTitle(leafCount: Int) -> Bool {
        leafCount <= 1
    }
}

enum WorkspaceTitlePresentation {
    static func displayTitle(
        titleOverride: String?,
        computedTitle: String,
        location: String?
    ) -> String {
        if let titleOverride, !titleOverride.isEmpty {
            return titleOverride
        }

        let trimmedTitle = computedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return "Workspace" }

        let withoutHostPrefix = stripHostPrefix(from: trimmedTitle)
        if let shortenedPathTitle = shortenPathLikeTitle(withoutHostPrefix, location: location) {
            return shortenedPathTitle
        }

        return withoutHostPrefix
    }

    private static func stripHostPrefix(from title: String) -> String {
        guard let separatorIndex = title.lastIndex(of: ":") else { return title }
        let prefix = title[..<separatorIndex]
        guard prefix.contains("@") else { return title }

        let suffixStart = title.index(after: separatorIndex)
        let suffix = title[suffixStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty ? title : suffix
    }

    private static func shortenPathLikeTitle(_ title: String, location: String?) -> String? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let abbreviatedLocation = location.map { ($0 as NSString).abbreviatingWithTildeInPath }

        let pathLikeTitle: String? = if trimmedTitle == "~" ||
            trimmedTitle.hasPrefix("~/") ||
            trimmedTitle.hasPrefix("/") {
            trimmedTitle
        } else if let abbreviatedLocation, trimmedTitle == abbreviatedLocation {
            abbreviatedLocation
        } else {
            nil
        }

        guard let pathLikeTitle else { return nil }
        if pathLikeTitle == "~" { return "Home" }

        let lastComponent = (pathLikeTitle as NSString).lastPathComponent
        return lastComponent.isEmpty ? pathLikeTitle : lastComponent
    }
}

enum WorkspaceCloseSelection {
    static func replacementID(
        in workspaces: [WorkspaceCloseSelectionEntry],
        closingID: String,
        activeWorkspaceID: String,
        previousWorkspaceID: String?,
        selectionHistory: [String]
    ) -> String? {
        let remaining = workspaces.filter { $0.id != closingID }
        guard !remaining.isEmpty else { return nil }

        let remainingByID = Dictionary(uniqueKeysWithValues: remaining.map { ($0.id, $0) })
        if closingID == activeWorkspaceID {
            if let previousWorkspaceID,
               previousWorkspaceID != closingID,
               let candidate = remainingByID[previousWorkspaceID],
               !candidate.isInactive {
                return candidate.id
            }

            for workspaceID in selectionHistory.reversed() {
                guard workspaceID != closingID else { continue }
                guard let candidate = remainingByID[workspaceID], !candidate.isInactive else { continue }
                return candidate.id
            }
        }

        let activeWorkspaces = workspaces.filter { !$0.isInactive }
        if let closingActiveIndex = activeWorkspaces.firstIndex(where: { $0.id == closingID }) {
            if closingActiveIndex > 0 {
                return activeWorkspaces[closingActiveIndex - 1].id
            }

            if closingActiveIndex + 1 < activeWorkspaces.count {
                return activeWorkspaces[closingActiveIndex + 1].id
            }
        }

        if let firstActive = remaining.first(where: { !$0.isInactive }) {
            return firstActive.id
        }

        guard let closingIndex = workspaces.firstIndex(where: { $0.id == closingID }) else {
            return remaining.first?.id
        }

        let fallbackIndex = min(closingIndex, remaining.count - 1)
        return remaining[fallbackIndex].id
    }
}

/// A classic, tabbed terminal experience.
class TerminalController: BaseTerminalController, TabGroupCloseCoordinator.Controller {
    @MainActor
    private final class WorkspaceState: Identifiable {
        let id: String
        var tree: SplitTree<Ghostty.SurfaceView>
        var focusedSurface = Weak<Ghostty.SurfaceView>()
        var titleOverride: String?
        var computedTitle: String = "👻"
        var location: String?
        var remoteSessions: [Ghostty.SurfaceView.ID: WorkspaceRemoteSessionKind] = [:]
        var lastActivityAt: Date = .now
        var inactiveAt: Date?
        var isInactive: Bool = false
        var savedActiveIndex: Int = 0
        var subscriptions: Set<AnyCancellable> = []

        var hasRunningCommand: Bool {
            tree.contains { $0.isCommandRunning }
        }

        init(
            id: String = UUID().uuidString,
            tree: SplitTree<Ghostty.SurfaceView>,
            focusedSurface: Ghostty.SurfaceView? = nil
        ) {
            self.id = id
            self.tree = tree
            self.focusedSurface = .init(focusedSurface)
        }

        func remoteSessionKind() -> WorkspaceRemoteSessionKind? {
            if let focusedSurface = focusedSurface.value,
               let kind = remoteSessions[focusedSurface.id] {
                return kind
            }

            for surfaceView in tree {
                if let kind = remoteSessions[surfaceView.id] {
                    return kind
                }
            }

            return remoteSessions.values.first
        }
    }

    override var windowNibName: NSNib.Name? {
        let defaultValue = "Terminal"

        guard let appDelegate = NSApp.delegate as? AppDelegate else { return defaultValue }
        let config = appDelegate.ghostty.config

        // If we have no window decorations, there's no reason to do anything but
        // the default titlebar (because there will be no titlebar).
        if !config.windowDecorations {
            return defaultValue
        }

        let nib = switch config.macosTitlebarStyle {
        case .native: "Terminal"
        case .hidden: "TerminalHiddenTitlebar"
        case .transparent: "TerminalTransparentTitlebar"
        case .tabs:
#if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                "TerminalTabsTitlebarTahoe"
            } else {
                "TerminalTabsTitlebarVentura"
            }
#else
            "TerminalTabsTitlebarVentura"
#endif
        }

        return nib
    }

    /// This is set to true when we care about frame changes. This is a small optimization since
    /// this controller registers a listener for ALL frame change notifications and this lets us bail
    /// early if we don't care.
    private var tabListenForFrame: Bool = false

    /// This is the hash value of the last tabGroup.windows array. We use this to detect order
    /// changes in the list.
    private var tabWindowsHash: Int = 0

    /// This is set to false by init if the window managed by this controller should not be restorable.
    /// For example, terminals executing custom scripts are not restorable.
    private var restorable: Bool = true

    /// The configuration derived from the Ghostty config so we don't need to rely on references.
    private(set) var derivedConfig: DerivedConfig

    /// The notification cancellable for focused surface property changes.
    private var surfaceAppearanceCancellables: Set<AnyCancellable> = []

    /// Shared sidebar state for the custom workspace list.
    private let workspaceSidebarViewModel = WorkspaceSidebarViewModel()
    private var workspaces: [WorkspaceState] = []
    private var activeWorkspaceID: String
    private var workspaceSelectionHistory: [String] = []
    private var previousActiveWorkspaceID: String?
    private var isApplyingWorkspaceState: Bool = false
    private var workspaceSidebarVisible: Bool = true
    private var workspaceSidebarWidth: CGFloat = 248

    private static let workspaceInactivityInterval: TimeInterval = 5 * 60

    init(_ ghostty: Ghostty.App,
         withBaseConfig base: Ghostty.SurfaceConfiguration? = nil,
         withSurfaceTree tree: SplitTree<Ghostty.SurfaceView>? = nil,
         parent: NSWindow? = nil
    ) {
        // The window we manage is not restorable if we've specified a command
        // to execute. We do this because the restored window is meaningless at the
        // time of writing this: it'd just restore to a shell in the same directory
        // as the script. We may want to revisit this behavior when we have scrollback
        // restoration.
        self.restorable = (base?.command ?? "") == ""

        // Setup our initial derived config based on the current app config
        self.derivedConfig = DerivedConfig(ghostty.config)
        let initialWorkspaceID = UUID().uuidString
        self.activeWorkspaceID = initialWorkspaceID

        super.init(ghostty, baseConfig: base, surfaceTree: tree)
        self.workspaces = [.init(id: initialWorkspaceID, tree: self.surfaceTree, focusedSurface: self.focusedSurface)]
        self.workspaces[0].computedTitle = self.lastComputedTitle
        self.workspaces[0].titleOverride = self.titleOverride
        self.workspaces[0].location = self.workspaceLocation
        self.workspaces[0].remoteSessions = self.workspaceRemoteSessions
        self.workspaces[0].lastActivityAt = self.workspaceLastActivityAt
        self.workspaces[0].savedActiveIndex = 0
        self.workspaceSelectionHistory = WorkspaceSelectionHistory.recordingSelection([], workspaceID: initialWorkspaceID)
        self.previousActiveWorkspaceID = nil
        rebuildWorkspaceObservers(for: self.workspaces[0])

        // Setup our notifications for behaviors
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(onToggleFullscreen),
            name: Ghostty.Notification.ghosttyToggleFullscreen,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(onMoveTab),
            name: .ghosttyMoveTab,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(onGotoTab),
            name: Ghostty.Notification.ghosttyGotoTab,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(onCloseTab),
            name: .ghosttyCloseTab,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(onCloseOtherTabs),
            name: .ghosttyCloseOtherTabs,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(onCloseTabsOnTheRight),
            name: .ghosttyCloseTabsOnTheRight,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(onResetWindowSize),
            name: .ghosttyResetWindowSize,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(ghosttyConfigDidChange(_:)),
            name: .ghosttyConfigDidChange,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(onFrameDidChange),
            name: NSView.frameDidChangeNotification,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(onCloseWindow),
            name: .ghosttyCloseWindow,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for this view")
    }

    deinit {
        // Remove all of our notificationcenter subscriptions
        let center = NotificationCenter.default
        center.removeObserver(self)
    }

    // MARK: Base Controller Overrides

    override func surfaceTreeDidChange(from: SplitTree<Ghostty.SurfaceView>, to: SplitTree<Ghostty.SurfaceView>) {
        super.surfaceTreeDidChange(from: from, to: to)

        // Whenever our surface tree changes in any way (new split, close split, etc.)
        // we want to invalidate our state.
        invalidateRestorableState()

        // Update our zoom state
        if let window = window as? TerminalWindow {
            window.surfaceIsZoomed = to.zoomed != nil
        }

        if isApplyingWorkspaceState { return }

        // If our surface tree is now nil then we close our window or workspace.
        if to.isEmpty {
            if workspaces.count > 1 {
                closeTabImmediately()
            } else {
                self.window?.close()
            }
            return
        }

        syncActiveWorkspaceFromController(rebuildObservers: true)
        refreshWorkspaceSidebar()
    }

    override func shouldTrackFocusedSurfaceTitle() -> Bool {
        WorkspaceAutomaticTitleTracking.shouldTrackComputedTitle(leafCount: surfaceTree.count)
    }

    override func replaceSurfaceTree(
        _ newTree: SplitTree<Ghostty.SurfaceView>,
        moveFocusTo newView: Ghostty.SurfaceView? = nil,
        moveFocusFrom oldView: Ghostty.SurfaceView? = nil,
        undoAction: String? = nil
    ) {
        // We have a special case if our tree is empty to close our tab immediately.
        if newTree.isEmpty {
            closeTabImmediately()
            return
        }

        super.replaceSurfaceTree(
            newTree,
            moveFocusTo: newView,
            moveFocusFrom: oldView,
            undoAction: undoAction)
    }

    // MARK: Terminal Creation

    /// Returns all the available terminal controllers present in the app currently.
    static var all: [TerminalController] {
        return NSApplication.shared.windows.compactMap {
            $0.windowController as? TerminalController
        }
    }

    // Keep track of the last point that our window was launched at so that new
    // windows "cascade" over each other and don't just launch directly on top
    // of each other.
    private static var lastCascadePoint = NSPoint(x: 0, y: 0)

    private static func applyCascade(to window: NSWindow, hasFixedPos: Bool) {
        if hasFixedPos { return }

        if all.count > 1 {
            lastCascadePoint = window.cascadeTopLeft(from: lastCascadePoint)
        } else {
            // We assume the window frame is already correct at this point,
            // so we pass .zero to let cascade use the current frame position.
            lastCascadePoint = window.cascadeTopLeft(from: .zero)
        }
    }

    // The preferred parent terminal controller.
    static var preferredParent: TerminalController? {
        all.first {
            $0.window?.isMainWindow ?? false
        } ?? lastMain ?? all.last
    }

    // The last controller to be main. We use this when paired with "preferredParent"
    // to find the preferred window to attach new tabs, perform actions, etc. We
    // always prefer the main window but if there isn't any (because we're triggered
    // by something like an App Intent) then we prefer the most previous main.
    static private(set) weak var lastMain: TerminalController?

    /// The "new window" action.
    static func newWindow(
        _ ghostty: Ghostty.App,
        withBaseConfig baseConfig: Ghostty.SurfaceConfiguration? = nil,
        withParent explicitParent: NSWindow? = nil
    ) -> TerminalController {
        let c = TerminalController.init(ghostty, withBaseConfig: baseConfig)

        // Get our parent. Our parent is the one explicitly given to us,
        // otherwise the focused terminal, otherwise an arbitrary one.
        let parent: NSWindow? = explicitParent ?? preferredParent?.window

        if let parent, parent.styleMask.contains(.fullScreen) {
            // If our previous window was fullscreen then we want our new window to
            // be fullscreen. This behavior actually doesn't match the native tabbing
            // behavior of macOS apps where new windows create tabs when in native
            // fullscreen but this is how we've always done it. This matches iTerm2
            // behavior.
            c.toggleFullscreen(mode: .native)
        } else if let fullscreenMode = ghostty.config.windowFullscreen {
            switch fullscreenMode {
            case .native:
                // Native has to be done immediately so that our stylemask contains
                // fullscreen for the logic later in this method.
                c.toggleFullscreen(mode: .native)

            case .nonNative, .nonNativeVisibleMenu, .nonNativePaddedNotch:
                // If we're non-native then we have to do it on a later loop
                // so that the content view is setup.
                DispatchQueue.main.async {
                    c.toggleFullscreen(mode: fullscreenMode)
                }
            }
        }

        // We're dispatching this async because otherwise the lastCascadePoint doesn't
        // take effect. Our best theory is there is some next-event-loop-tick logic
        // that Cocoa is doing that we need to be after.
        DispatchQueue.main.async {
            c.showWindow(self)

            // Only cascade if we aren't fullscreen.
            if let window = c.window {
                if !window.styleMask.contains(.fullScreen) {
                    let hasFixedPos = c.derivedConfig.windowPositionX != nil && c.derivedConfig.windowPositionY != nil
                    Self.applyCascade(to: window, hasFixedPos: hasFixedPos)
                }
            }

            // All new_window actions force our app to be active, so that the new
            // window is focused and visible.
            NSApp.activate(ignoringOtherApps: true)
        }

        // Setup our undo
        if let undoManager = c.undoManager {
            undoManager.setActionName("New Window")
            undoManager.registerUndo(
                withTarget: c,
                expiresAfter: c.undoExpiration
            ) { target in
                // Close the window when undoing
                undoManager.disableUndoRegistration {
                    target.closeWindow(nil)
                }

                // Register redo action
                undoManager.registerUndo(
                    withTarget: ghostty,
                    expiresAfter: target.undoExpiration
                ) { ghostty in
                    _ = TerminalController.newWindow(
                        ghostty,
                        withBaseConfig: baseConfig,
                        withParent: explicitParent)
                }
            }
        }

        return c
    }

    /// Create a new window with an existing split tree.
    /// The window will be sized to match the tree's current view bounds if available.
    /// - Parameters:
    ///   - ghostty: The Ghostty app instance.
    ///   - tree: The split tree to use for the new window.
    ///   - position: Optional screen position (top-left corner) for the new window.
    ///               If nil, the window will cascade from the last cascade point.
    static func newWindow(
        _ ghostty: Ghostty.App,
        tree: SplitTree<Ghostty.SurfaceView>,
        position: NSPoint? = nil,
        confirmUndo: Bool = true,
    ) -> TerminalController {
        let c = TerminalController.init(ghostty, withSurfaceTree: tree)

        // Calculate the target frame based on the tree's view bounds
        let treeSize: CGSize? = tree.root?.viewBounds()

        DispatchQueue.main.async {
            c.showWindow(self)
            if let window = c.window {
                // If we have a tree size, resize the window's content to match
                if let treeSize, treeSize.width > 0, treeSize.height > 0 {
                    window.setContentSize(treeSize)
                    window.constrainToScreen()
                }

                if !window.styleMask.contains(.fullScreen) {
                    if let position {
                        window.setFrameTopLeftPoint(position)
                        window.constrainToScreen()
                    } else {
                        let hasFixedPos = c.derivedConfig.windowPositionX != nil && c.derivedConfig.windowPositionY != nil
                        Self.applyCascade(to: window, hasFixedPos: hasFixedPos)
                    }
                }
            }
        }

        // Setup our undo
        if let undoManager = c.undoManager {
            undoManager.setActionName("New Window")
            undoManager.registerUndo(
                withTarget: c,
                expiresAfter: c.undoExpiration
            ) { target in
                undoManager.disableUndoRegistration {
                    if confirmUndo {
                        target.closeWindow(nil)
                    } else {
                        target.closeWindowImmediately()
                    }
                }

                undoManager.registerUndo(
                    withTarget: ghostty,
                    expiresAfter: target.undoExpiration
                ) { ghostty in
                    _ = TerminalController.newWindow(ghostty, tree: tree)
                }
            }
        }

        return c
    }

    static func newTab(
        _ ghostty: Ghostty.App,
        from parent: NSWindow? = nil,
        withBaseConfig baseConfig: Ghostty.SurfaceConfiguration? = nil
    ) -> TerminalController? {
        guard let parent,
              let parentController = parent.windowController as? TerminalController else {
            return newWindow(ghostty, withBaseConfig: baseConfig, withParent: parent)
        }

        parentController.addWorkspace(withBaseConfig: baseConfig)
        return parentController
    }

    static func newWorkspace(
        _ ghostty: Ghostty.App,
        from parent: NSWindow? = nil,
        withBaseConfig baseConfig: Ghostty.SurfaceConfiguration? = nil
    ) -> TerminalController? {
        newTab(ghostty, from: parent, withBaseConfig: baseConfig)
    }

    // MARK: - Methods

    @objc private func ghosttyConfigDidChange(_ notification: Notification) {
        // Get our managed configuration object out
        guard let config = notification.userInfo?[
            Notification.Name.GhosttyConfigChangeKey
        ] as? Ghostty.Config else { return }

        // If this is an app-level config update then we update some things.
        if notification.object == nil {
            // Update our derived config
            self.derivedConfig = DerivedConfig(config)

            // If we have no surfaces in our window (is that possible?) then we update
            // our window appearance based on the root config. If we have surfaces, we
            // don't call this because focused surface changes will trigger appearance updates.
            if surfaceTree.isEmpty {
                syncAppearance(.init(config))
            }

            return
        }
        /// Surface-level config will be updated in
        /// ``Ghostty/Ghostty/SurfaceView/derivedConfig`` then
        /// ``TerminalController/focusedSurfaceDidChange(to:)``
    }

    /// Update the accessory view of each tab according to the keyboard
    /// shortcut that activates it (if any). This is called when the key window
    /// changes, when a window is closed, and when tabs are reordered
    /// with the mouse.
    func relabelTabs() {
        tabListenForFrame = false
        refreshWorkspaceSidebarGroup()
    }

    private func configureWorkspaceSidebarActions() {
        workspaceSidebarViewModel.selectWorkspace = { [weak self] id in
            self?.selectWorkspace(withID: id)
        }
        workspaceSidebarViewModel.moveWorkspace = { [weak self] sourceID, insertionIndex in
            self?.moveWorkspace(sourceID: sourceID, toActiveInsertionIndex: insertionIndex)
        }
        workspaceSidebarViewModel.detachWorkspace = { [weak self] id in
            self?.detachWorkspaceToWindow(id: id)
        }
        workspaceSidebarViewModel.renameSelectedWorkspace = { [weak self] in
            self?.promptTabTitle()
        }
        workspaceSidebarViewModel.newWorkspace = { [weak self] in
            guard let self else { return }
            _ = Self.newWorkspace(self.ghostty, from: self.window)
        }
    }

    private var activeWorkspaceState: WorkspaceState? {
        workspaces.first(where: { $0.id == activeWorkspaceID })
    }

    private func makeWorkspaceState(
        withBaseConfig baseConfig: Ghostty.SurfaceConfiguration? = nil,
        tree: SplitTree<Ghostty.SurfaceView>? = nil
    ) -> WorkspaceState? {
        let workspaceTree: SplitTree<Ghostty.SurfaceView>
        if let tree {
            workspaceTree = tree
        } else {
            guard let ghosttyApp = ghostty.app else { return nil }
            workspaceTree = .init(view: Ghostty.SurfaceView(ghosttyApp, baseConfig: baseConfig))
        }

        let focusedSurface = workspaceTree.first

        let workspace = WorkspaceState(tree: workspaceTree, focusedSurface: focusedSurface)
        workspace.savedActiveIndex = workspaces.filter { !$0.isInactive }.count
        rebuildWorkspaceObservers(for: workspace)
        return workspace
    }

    private func addWorkspace(withBaseConfig baseConfig: Ghostty.SurfaceConfiguration? = nil) {
        guard let workspace = makeWorkspaceState(withBaseConfig: baseConfig) else { return }

        syncActiveWorkspaceFromController()

        let activeCount = workspaces.filter { !$0.isInactive }.count
        let insertionIndex: Int = switch ghostty.config.windowNewTabPosition {
        case "end":
            activeCount
        case "current":
            if let currentIndex = workspaces.firstIndex(where: { $0.id == activeWorkspaceID }) {
                min(currentIndex + 1, activeCount)
            } else {
                activeCount
            }
        default:
            activeCount
        }

        workspaces.insert(workspace, at: insertionIndex)
        syncWorkspaceSavedActiveIndices()
        switchWorkspace(to: workspace.id)
    }

    func refreshWorkspaceSidebarGroup() {
        guard !isApplyingWorkspaceState else { return }
        syncActiveWorkspaceFromController()
        refreshWorkspaceSidebar()
    }

    private func refreshWorkspaceSidebar() {
        let showSidebar = supportsWorkspaceSidebar && workspaceSidebarVisible
        let sidebarTheme = makeWorkspaceSidebarTheme()
        let rootView: AnyView? = if showSidebar {
            AnyView(WorkspaceSidebarView(viewModel: workspaceSidebarViewModel))
        } else {
            nil
        }
        if let window = window as? TerminalWindow {
            window.workspaceSidebarActive = supportsWorkspaceSidebar
            window.tabbingMode = .disallowed
        }
        workspaceSidebarViewModel.rows = workspaceRowsForSidebar()
        workspaceSidebarViewModel.theme = sidebarTheme
        terminalViewContainer?.updateWorkspaceSidebarDividerColor(NSColor(sidebarTheme.divider))
        terminalViewContainer?.updateWorkspaceSidebar(
            rootView: rootView,
            width: workspaceSidebarWidth
        )
    }

    private var supportsWorkspaceSidebar: Bool {
        true
    }

    private func workspaceRowsForSidebar() -> [WorkspaceSidebarRow] {
        workspaces.map { workspace in
            WorkspaceSidebarRow(
                id: workspace.id,
                title: workspaceDisplayTitle(for: workspace),
                subtitle: workspaceDisplayLocation(for: workspace),
                remoteSessionLabel: workspace.remoteSessionKind()?.badgeLabel,
                hasRunningCommand: workspace.hasRunningCommand,
                isSelected: workspace.id == activeWorkspaceID,
                isInactive: workspace.isInactive
            )
        }
    }

    private func workspaceDisplayTitle(for workspace: WorkspaceState) -> String {
        WorkspaceTitlePresentation.displayTitle(
            titleOverride: workspace.titleOverride,
            computedTitle: workspace.computedTitle,
            location: workspace.location
        )
    }

    private func workspaceDisplayLocation(for workspace: WorkspaceState) -> String? {
        guard let location = workspace.location, !location.isEmpty else { return nil }
        return (location as NSString).abbreviatingWithTildeInPath
    }

    private func makeWorkspaceSidebarTheme() -> WorkspaceSidebarTheme {
        let baseBackground = (
            (window as? TerminalWindow)?.preferredBackgroundColor?.withAlphaComponent(1) ??
            NSColor(ghostty.config.backgroundColor).withAlphaComponent(1)
        )
        let isLight = baseBackground.isLightColor
        let background = blendedSidebarColor(
            baseBackground,
            fraction: isLight ? 0.08 : 0.06,
            with: isLight ? .black : .white
        )
        let divider = blendedSidebarColor(
            background,
            fraction: isLight ? 0.14 : 0.16,
            with: isLight ? .black : .white
        )
        let rowSelection = blendedSidebarColor(
            background,
            fraction: isLight ? 0.16 : 0.18,
            with: isLight ? .black : .white
        )
        let inactiveBackground = blendedSidebarColor(
            background,
            fraction: isLight ? 0.04 : 0.08,
            with: isLight ? .black : .white
        ).withAlphaComponent(isLight ? 0.42 : 0.52)
        let titleColor = isLight
            ? NSColor(calibratedWhite: 0.08, alpha: 0.96)
            : NSColor(calibratedWhite: 0.95, alpha: 0.96)
        let subtitleColor = isLight
            ? NSColor(calibratedWhite: 0.22, alpha: 0.86)
            : NSColor(calibratedWhite: 0.78, alpha: 0.82)
        let inactiveTitleColor = titleColor.withAlphaComponent(isLight ? 0.52 : 0.5)
        let inactiveSubtitleColor = subtitleColor.withAlphaComponent(isLight ? 0.44 : 0.46)
        let badgeBaseColor = NSColor.controlAccentColor
        let badgeBackground = blendedSidebarColor(
            background,
            fraction: isLight ? 0.18 : 0.24,
            with: badgeBaseColor
        ).withAlphaComponent(isLight ? 0.92 : 0.9)
        let badgeForeground = isLight
            ? badgeBaseColor.shadow(withLevel: 0.12) ?? badgeBaseColor
            : badgeBaseColor.highlight(withLevel: 0.1) ?? badgeBaseColor

        return .init(
            background: Color(nsColor: background),
            divider: Color(nsColor: divider),
            rowSelection: Color(nsColor: rowSelection),
            rowInactiveBackground: Color(nsColor: inactiveBackground),
            title: Color(nsColor: titleColor),
            subtitle: Color(nsColor: subtitleColor),
            inactiveTitle: Color(nsColor: inactiveTitleColor),
            inactiveSubtitle: Color(nsColor: inactiveSubtitleColor),
            badgeBackground: Color(nsColor: badgeBackground),
            badgeForeground: Color(nsColor: badgeForeground),
            colorScheme: isLight ? .light : .dark
        )
    }

    private func blendedSidebarColor(
        _ background: NSColor,
        fraction: CGFloat,
        with color: NSColor
    ) -> NSColor {
        background.blended(withFraction: fraction, of: color) ?? background
    }

    private func switchWorkspace(to workspaceID: String) {
        guard workspaces.contains(where: { $0.id == workspaceID }) else { return }
        guard workspaceID != activeWorkspaceID else {
            refreshWorkspaceSidebar()
            return
        }

        let previousWorkspaceID = activeWorkspaceID
        syncActiveWorkspaceFromController()
        activeWorkspaceID = workspaceID
        previousActiveWorkspaceID = previousWorkspaceID
        recordWorkspaceSelection(workspaceID)
        restoreActiveWorkspaceState()
        refreshWorkspaceSidebar()
    }

    private func selectWorkspace(withID id: String) {
        if let target = workspaces.first(where: { $0.id == id }), target.isInactive {
            reactivateWorkspace(id: target.id, selectAfterReordering: true)
            return
        }

        switchWorkspace(to: id)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        recordWorkspaceUserActivity()
    }

    private func moveWorkspace(sourceID: String, toActiveInsertionIndex insertionIndex: Int) {
        syncActiveWorkspaceFromController()
        guard workspaces.count > 1 else { return }

        var active = workspaces.filter { !$0.isInactive }
        let inactive = workspaces.filter(\.isInactive)
        guard let sourceIndex = active.firstIndex(where: { $0.id == sourceID }) else { return }
        let activeCount = active.count
        guard let destinationIndex = WorkspaceSidebarReorderDestination.destinationIndex(
            sourceIndex: sourceIndex,
            proposedDestinationIndex: insertionIndex,
            itemCount: activeCount
        ) else {
            refreshWorkspaceSidebar()
            return
        }

        let moving = active.remove(at: sourceIndex)
        active.insert(moving, at: min(destinationIndex, active.count))
        workspaces = active + inactive
        syncWorkspaceSavedActiveIndices()
        refreshWorkspaceSidebar()
    }

    private func moveActiveWorkspace(by offset: Int) {
        guard offset != 0 else { return }
        syncActiveWorkspaceFromController()

        var activeWorkspaces = workspaces.filter { !$0.isInactive }
        guard activeWorkspaces.count > 1 else { return }
        guard let selectedIndex = activeWorkspaces.firstIndex(where: { $0.id == activeWorkspaceID }) else { return }

        let finalIndex: Int
        if offset < 0 {
            finalIndex = max(selectedIndex + offset, 0)
        } else {
            finalIndex = min(selectedIndex + offset, activeWorkspaces.count - 1)
        }

        guard finalIndex != selectedIndex else { return }

        let moving = activeWorkspaces.remove(at: selectedIndex)
        activeWorkspaces.insert(moving, at: finalIndex)
        let inactiveWorkspaces = workspaces.filter(\.isInactive)
        workspaces = activeWorkspaces + inactiveWorkspaces
        syncWorkspaceSavedActiveIndices()
        refreshWorkspaceSidebar()
    }

    private func selectWorkspace(by offset: Int) {
        guard offset != 0 else { return }
        syncActiveWorkspaceFromController()

        let orderedWorkspaces = workspaces
        guard !orderedWorkspaces.isEmpty else { return }
        guard let selectedIndex = orderedWorkspaces.firstIndex(where: { $0.id == activeWorkspaceID }) else { return }

        let finalIndex: Int
        if offset < 0 {
            finalIndex = max(selectedIndex + offset, 0)
        } else {
            finalIndex = min(selectedIndex + offset, orderedWorkspaces.count - 1)
        }

        guard finalIndex != selectedIndex else { return }
        selectWorkspace(withID: orderedWorkspaces[finalIndex].id)
    }

    private func detachWorkspaceToWindow(id: String) {
        syncActiveWorkspaceFromController()
        guard workspaces.count > 1 else {
            refreshWorkspaceSidebar()
            return
        }
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == id }) else { return }

        let workspace = workspaces.remove(at: workspaceIndex)
        let replacementID = WorkspaceCloseSelection.replacementID(
            in: workspaceCloseSelectionEntries(),
            closingID: id,
            activeWorkspaceID: activeWorkspaceID,
            previousWorkspaceID: previousActiveWorkspaceID,
            selectionHistory: workspaceSelectionHistory
        )

        workspaceSelectionHistory.removeAll { $0 == id }
        if previousActiveWorkspaceID == id {
            previousActiveWorkspaceID = workspaceSelectionHistory.last(where: { $0 != activeWorkspaceID })
        }

        if activeWorkspaceID == id, let replacementID {
            activeWorkspaceID = replacementID
            restoreActiveWorkspaceState()
        }

        syncWorkspaceSavedActiveIndices()
        pruneWorkspaceSelectionHistory()
        refreshWorkspaceSidebar()

        let controller = Self.newWindow(ghostty, tree: workspace.tree, confirmUndo: false)
        controller.titleOverride = workspace.titleOverride
        DispatchQueue.main.async {
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func evaluateWorkspaceInactivity(referenceDate: Date) {
        syncActiveWorkspaceFromController()

        for workspace in workspaces where !workspace.isInactive {
            guard referenceDate.timeIntervalSince(workspace.lastActivityAt) >= Self.workspaceInactivityInterval else { continue }
            makeWorkspaceInactive(id: workspace.id, referenceDate: referenceDate)
        }
    }

    private func makeWorkspaceInactive(id: String, referenceDate: Date) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        guard !workspace.isInactive else { return }

        let nextActiveWorkspaceID: String? = if id == activeWorkspaceID {
            workspaces.first(where: { $0.id != id && !$0.isInactive })?.id
        } else {
            nil
        }

        let activeWorkspaces = workspaces.filter { !$0.isInactive }
        workspace.savedActiveIndex = activeWorkspaces.firstIndex(where: { $0.id == id }) ?? workspace.savedActiveIndex
        workspace.isInactive = true
        workspace.inactiveAt = referenceDate

        reorderWorkspaces()

        if id == activeWorkspaceID {
            updateWorkspaceActivityState(inactive: true, inactiveAt: referenceDate, notifySidebar: false)
        }

        if let nextActiveWorkspaceID {
            switchWorkspace(to: nextActiveWorkspaceID)
        } else {
            refreshWorkspaceSidebar()
        }
    }

    func reactivateWorkspace(_ controller: BaseTerminalController, selectAfterReordering: Bool) {
        guard controller === self else { return }
        reactivateWorkspace(id: activeWorkspaceID, selectAfterReordering: selectAfterReordering)
    }

    func reactivateWorkspace(id: String, selectAfterReordering: Bool) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        guard workspace.isInactive else {
            if selectAfterReordering {
                switchWorkspace(to: id)
            }
            return
        }

        workspace.isInactive = false
        workspace.inactiveAt = nil
        workspace.lastActivityAt = .now

        let active = workspaces.filter { !$0.isInactive && $0.id != id }
        let inactive = workspaces.filter { $0.isInactive && $0.id != id }
        let insertIndex = min(workspace.savedActiveIndex, active.count)
        workspaces = Array(active.prefix(insertIndex)) + [workspace] + Array(active.dropFirst(insertIndex)) + inactive
        syncWorkspaceSavedActiveIndices()

        if selectAfterReordering {
            switchWorkspace(to: id)
        } else {
            refreshWorkspaceSidebar()
        }
    }

    private func reorderWorkspaces() {
        let active = workspaces.filter { !$0.isInactive }
        let inactive = workspaces
            .filter(\.isInactive)
            .sorted { lhs, rhs in
                (lhs.inactiveAt ?? .distantPast) > (rhs.inactiveAt ?? .distantPast)
            }
        workspaces = active + inactive
        syncWorkspaceSavedActiveIndices()
    }

    private func syncWorkspaceSavedActiveIndices() {
        let activeWorkspaces = workspaces.filter { !$0.isInactive }
        for (index, workspace) in activeWorkspaces.enumerated() {
            workspace.savedActiveIndex = index
        }
    }

    private func pruneWorkspaceSelectionHistory() {
        workspaceSelectionHistory = WorkspaceSelectionHistory.pruned(
            workspaceSelectionHistory,
            validWorkspaceIDs: Set(workspaces.map(\.id))
        )
        if let previousActiveWorkspaceID,
           workspaces.contains(where: { $0.id == previousActiveWorkspaceID }) {
            return
        }

        previousActiveWorkspaceID = workspaceSelectionHistory.last(where: { $0 != activeWorkspaceID })
    }

    private func recordWorkspaceSelection(_ workspaceID: String) {
        workspaceSelectionHistory = WorkspaceSelectionHistory.recordingSelection(
            workspaceSelectionHistory,
            workspaceID: workspaceID
        )
    }

    private func workspaceCloseSelectionEntries() -> [WorkspaceCloseSelectionEntry] {
        workspaces.map { .init(id: $0.id, isInactive: $0.isInactive) }
    }

    private func syncActiveWorkspaceFromController(rebuildObservers: Bool = false) {
        guard let workspace = activeWorkspaceState else { return }
        workspace.tree = surfaceTree
        workspace.focusedSurface.value = focusedSurface
        workspace.titleOverride = titleOverride
        workspace.computedTitle = lastComputedTitle
        workspace.location = workspaceLocation
        workspace.remoteSessions = workspaceRemoteSessions
        workspace.lastActivityAt = workspaceLastActivityAt
        workspace.isInactive = workspaceIsInactive
        workspace.inactiveAt = workspaceInactiveAt
        workspace.savedActiveIndex = workspaceSavedActiveIndex
        if rebuildObservers {
            rebuildWorkspaceObservers(for: workspace)
        }
    }

    private func restoreActiveWorkspaceState() {
        guard let workspace = activeWorkspaceState else { return }
        isApplyingWorkspaceState = true
        defer { isApplyingWorkspaceState = false }

        surfaceTree = workspace.tree
        focusedSurface = if let candidate = workspace.focusedSurface.value, surfaceTree.contains(candidate) {
            candidate
        } else {
            surfaceTree.first
        }
        titleOverride = workspace.titleOverride
        setWorkspaceComputedTitle(workspace.computedTitle, notifySidebar: false)
        setWorkspaceDisplayLocation(workspace.location, notifySidebar: false)
        setWorkspaceRemoteSessions(workspace.remoteSessions, notifySidebar: false)
        updateWorkspaceActivityState(
            inactive: workspace.isInactive,
            inactiveAt: workspace.inactiveAt,
            notifySidebar: false
        )
        setWorkspaceLastActivity(workspace.lastActivityAt, notifySidebar: false)
        workspaceSavedActiveIndex = workspace.savedActiveIndex

        if let surface = focusedSurface {
            DispatchQueue.main.async {
                Ghostty.moveFocus(to: surface)
            }
        }
    }

    private func rebuildWorkspaceObservers(for workspace: WorkspaceState) {
        workspace.subscriptions.removeAll()
        workspace.remoteSessions = workspace.remoteSessions.filter { remoteSession in
            workspace.tree.contains { $0.id == remoteSession.key }
        }

        for surfaceView in workspace.tree {
            NotificationCenter.default.publisher(
                for: .ghosttyDidUpdateScrollbar,
                object: surfaceView
            )
            .sink { [weak self] _ in
                self?.workspaceObservedActivity(workspaceID: workspace.id)
            }
            .store(in: &workspace.subscriptions)

            surfaceView.$title
                .dropFirst()
                .sink { [weak self, weak surfaceView] title in
                    if let surfaceView,
                       let remoteSession = WorkspaceRemoteSessionKind.detect(in: title) {
                        workspace.remoteSessions[surfaceView.id] = remoteSession
                    }
                    self?.workspaceSurfaceTitleChanged(
                        workspaceID: workspace.id,
                        surface: surfaceView,
                        title: title
                    )
                }
                .store(in: &workspace.subscriptions)

            surfaceView.$pwd
                .dropFirst()
                .sink { [weak self, weak surfaceView] pwd in
                    if let surfaceView {
                        workspace.remoteSessions.removeValue(forKey: surfaceView.id)
                    }
                    self?.workspaceSurfaceLocationChanged(
                        workspaceID: workspace.id,
                        surface: surfaceView,
                        location: pwd
                    )
                }
                .store(in: &workspace.subscriptions)

            surfaceView.$progressReport
                .dropFirst()
                .sink { [weak self] _ in
                    self?.workspaceObservedActivity(workspaceID: workspace.id)
                }
                .store(in: &workspace.subscriptions)

            surfaceView.$isCommandRunning
                .dropFirst()
                .sink { [weak self] _ in
                    self?.refreshWorkspaceSidebar()
                }
                .store(in: &workspace.subscriptions)
        }
    }

    private func workspaceObservedActivity(workspaceID: String, refreshSidebar: Bool = false) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        workspace.lastActivityAt = .now

        if workspaceID == activeWorkspaceID {
            setWorkspaceLastActivity(workspace.lastActivityAt)
        }

        if workspace.isInactive {
            reactivateWorkspace(id: workspaceID, selectAfterReordering: false)
        } else if refreshSidebar {
            refreshWorkspaceSidebar()
        }
    }

    private func workspaceSurfaceTitleChanged(
        workspaceID: String,
        surface: Ghostty.SurfaceView?,
        title: String
    ) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        if workspace.focusedSurface.value == nil {
            workspace.focusedSurface.value = surface
        }
        if workspace.focusedSurface.value === surface &&
            WorkspaceAutomaticTitleTracking.shouldTrackComputedTitle(leafCount: workspace.tree.count) {
            workspace.computedTitle = title.isEmpty ? "👻" : title
            if workspaceID == activeWorkspaceID {
                setWorkspaceComputedTitle(workspace.computedTitle, notifySidebar: false)
            }
        }
        workspaceObservedActivity(workspaceID: workspaceID, refreshSidebar: true)
    }

    private func workspaceSurfaceLocationChanged(
        workspaceID: String,
        surface: Ghostty.SurfaceView?,
        location: String?
    ) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        if workspace.focusedSurface.value == nil {
            workspace.focusedSurface.value = surface
        }
        if workspace.focusedSurface.value === surface {
            workspace.location = location
            if workspaceID == activeWorkspaceID {
                setWorkspaceDisplayLocation(location, notifySidebar: false)
            }
        }
        workspaceObservedActivity(workspaceID: workspaceID, refreshSidebar: true)
    }

    private func fixTabBar() {
        // We do this to make sure that the tab bar will always re-composite. If we don't,
        // then the it will "drag" pieces of the background with it when a transparent
        // window is moved around.
        //
        // There might be a better way to make the tab bar "un-lazy", but I can't find it.
        if let window = window, !window.isOpaque {
            window.isOpaque = true
            window.isOpaque = false
        }
    }

    @objc private func onFrameDidChange(_ notification: NSNotification) {
        // This is a huge hack to set the proper shortcut for tab selection
        // on tab reordering using the mouse. There is no event, delegate, etc.
        // as far as I can tell for when a tab is manually reordered with the
        // mouse in a macOS-native tab group, so the way we detect it is setting
        // the accessoryView "postsFrameChangedNotification" to true, listening
        // for the view frame to change, comparing the windows list, and
        // relabeling the tabs.
        guard tabListenForFrame else { return }
        guard let v = self.window?.tabbedWindows?.hashValue else { return }
        guard tabWindowsHash != v else { return }
        tabWindowsHash = v
        self.relabelTabs()
    }

    override func syncAppearance() {
        // When our focus changes, we update our window appearance based on the
        // currently focused surface.
        guard let focusedSurface else { return }
        syncAppearance(focusedSurface.derivedConfig)
    }

    private func syncAppearance(_ surfaceConfig: Ghostty.SurfaceView.DerivedConfig) {
        // Let our window handle its own appearance
        guard let window = window as? TerminalWindow else { return }

        // Sync our zoom state for splits
        window.surfaceIsZoomed = surfaceTree.zoomed != nil

        // Set the font for the window and tab titles.
        if let titleFontName = surfaceConfig.windowTitleFontFamily {
            window.titlebarFont = NSFont(name: titleFontName, size: NSFont.systemFontSize)
        } else {
            window.titlebarFont = nil
        }

        // Call this last in case it uses any of the properties above.
        window.syncAppearance(surfaceConfig)
        terminalViewContainer?.ghosttyConfigDidChange(ghostty.config, preferredBackgroundColor: window.preferredBackgroundColor)
        refreshWorkspaceSidebar()
    }

    /// Adjusts the given frame for the configured window position.
    func adjustForWindowPosition(frame: NSRect, on screen: NSScreen) -> NSRect {
        guard let x = derivedConfig.windowPositionX else { return frame }
        guard let y = derivedConfig.windowPositionY else { return frame }

        // Convert top-left coordinates to bottom-left origin using our utility extension
        let origin = screen.origin(
            fromTopLeftOffsetX: CGFloat(x),
            offsetY: CGFloat(y),
            windowSize: frame.size)

        // Clamp the origin to ensure the window stays fully visible on screen
        var safeOrigin = origin
        let vf = screen.visibleFrame
        safeOrigin.x = min(max(safeOrigin.x, vf.minX), vf.maxX - frame.width)
        safeOrigin.y = min(max(safeOrigin.y, vf.minY), vf.maxY - frame.height)

        // Return our new origin
        var result = frame
        result.origin = safeOrigin
        return result
    }

    /// This is called anytime a node in the surface tree is being removed.
    override func closeSurface(
        _ node: SplitTree<Ghostty.SurfaceView>.Node,
        withConfirmation: Bool = true
    ) {
        // If this isn't the root then we're dealing with a split closure.
        if surfaceTree.root != node {
            super.closeSurface(node, withConfirmation: withConfirmation)
            return
        }

        // More than 1 workspace means we close only the selected workspace.
        if workspaces.count > 1 {
            closeTab(nil)
            return
        }

        // 1 window, closing the window
        closeWindow(nil)
    }

    func closeTabImmediately(registerRedo: Bool = true) {
        syncActiveWorkspaceFromController()

        guard workspaces.count > 1 else {
            closeWindowImmediately()
            return
        }

        guard let currentIndex = workspaces.firstIndex(where: { $0.id == activeWorkspaceID }) else {
            closeWindowImmediately()
            return
        }

        let closeSelectionEntries = workspaceCloseSelectionEntries()
        let previousWorkspaceID = previousActiveWorkspaceID
        let removedWorkspace = workspaces.remove(at: currentIndex)
        removedWorkspace.subscriptions.removeAll()
        pruneWorkspaceSelectionHistory()

        guard !workspaces.isEmpty else {
            closeWindowImmediately()
            return
        }

        let replacementWorkspaceID = WorkspaceCloseSelection.replacementID(
            in: closeSelectionEntries,
            closingID: removedWorkspace.id,
            activeWorkspaceID: removedWorkspace.id,
            previousWorkspaceID: previousWorkspaceID,
            selectionHistory: workspaceSelectionHistory
        )

        guard
            let replacementWorkspaceID,
            let replacementWorkspace = workspaces.first(where: { $0.id == replacementWorkspaceID })
        else {
            closeWindowImmediately()
            return
        }

        activeWorkspaceID = replacementWorkspace.id
        recordWorkspaceSelection(replacementWorkspace.id)
        previousActiveWorkspaceID = workspaceSelectionHistory.last(where: { $0 != replacementWorkspace.id })
        syncWorkspaceSavedActiveIndices()
        restoreActiveWorkspaceState()
        refreshWorkspaceSidebar()
    }

    private func closeOtherTabsImmediately() {
        syncActiveWorkspaceFromController()
        workspaces = workspaces.filter { $0.id == activeWorkspaceID }
        pruneWorkspaceSelectionHistory()
        syncWorkspaceSavedActiveIndices()
        refreshWorkspaceSidebar()
    }

    private func closeTabsOnTheRightImmediately() {
        syncActiveWorkspaceFromController()
        guard let currentIndex = workspaces.firstIndex(where: { $0.id == activeWorkspaceID }) else { return }
        guard currentIndex < workspaces.count - 1 else { return }

        for workspace in workspaces[(currentIndex + 1)...] {
            workspace.subscriptions.removeAll()
        }
        workspaces.removeSubrange((currentIndex + 1)..<workspaces.count)
        pruneWorkspaceSelectionHistory()
        syncWorkspaceSavedActiveIndices()
        refreshWorkspaceSidebar()
    }

    /// Closes the current window (including any other tabs) immediately and without
    /// confirmation. This will setup proper undo state so the action can be undone.
    func closeWindowImmediately() {
        guard let window = window else { return }

        registerUndoForCloseWindow()

        if let tabGroup = window.tabGroup, tabGroup.windows.count > 1 {
            tabGroup.windows.forEach { window in
                // Clear out the surfacetree to ensure there is no undo state.
                // This prevents unnecessary undos registered since AppKit may
                // process them on later ticks so we can't just disable undo registration.
                if let controller = window.windowController as? TerminalController {
                    controller.surfaceTree = .init()
                }

                window.close()
            }
        } else {
            window.close()
        }
    }

    /// Registers undo for closing window(s), handling both single windows and tab groups.
    private func registerUndoForCloseWindow() {
        guard let undoManager, undoManager.isUndoRegistrationEnabled else { return }
        guard let window else { return }

        // If we don't have a tab group or we don't have multiple tabs, then
        // do a normal single window close.
        guard let tabGroup = window.tabGroup,
              tabGroup.windows.count > 1 else {
            // No tabs, just save this window's state
            if let undoState {
                // Register undo action to restore the window
                undoManager.setActionName("Close Window")
                undoManager.registerUndo(
                    withTarget: ghostty,
                    expiresAfter: undoExpiration) { ghostty in
                        // Restore the undo state
                        let newController = TerminalController(ghostty, with: undoState)

                        // Register redo action
                        undoManager.registerUndo(
                            withTarget: newController,
                            expiresAfter: newController.undoExpiration) { target in
                                target.closeWindowImmediately()
                            }
                    }
            }

            return
        }

        // Multiple windows in tab group - collect all undo states in sorted order
        // by tab ordering. Also track which window was key.
        let undoStates = tabGroup.windows
            .compactMap { tabWindow -> UndoState? in
                guard let controller = tabWindow.windowController as? TerminalController,
                      var undoState = controller.undoState else { return nil }
                // Clear the tab group reference since it is unneeded. It should be
                // garbage collected but we want to be extra sure we don't try to
                // restore into it because we're going to recreate it.
                undoState.tabGroup = nil
                return undoState
            }
            .sorted { (lhs, rhs) in
                switch (lhs.tabIndex, rhs.tabIndex) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return true
                }
            }

        // Find the index of the key window in our sorted states. This is a bit verbose
        // but we only need this for this style of undo so we don't want to add it to
        // UndoState.
        let keyWindowIndex: Int?
        if let keyWindow = tabGroup.windows.first(where: { $0.isKeyWindow }),
            let keyController = keyWindow.windowController as? TerminalController,
            let keyUndoState = keyController.undoState {
            keyWindowIndex = undoStates.firstIndex {
                $0.tabIndex == keyUndoState.tabIndex }
        } else {
            keyWindowIndex = nil
        }

        // Register undo action to restore all windows
        guard !undoStates.isEmpty else { return }

        undoManager.setActionName("Close Window")
        undoManager.registerUndo(
            withTarget: ghostty,
            expiresAfter: undoExpiration
        ) { ghostty in
            // Restore all windows in the tab group
            let controllers = undoStates.map { undoState in
                TerminalController(ghostty, with: undoState)
            }

            // The first controller becomes the parent window for all tabs.
            // If we don't have a first controller (shouldn't be possible?)
            // then we can't restore tabs.
            guard let firstController = controllers.first else { return }

            // Add all subsequent controllers as tabs to the first window
            for controller in controllers.dropFirst() {
                controller.showWindow(nil)
                if let firstWindow = firstController.window,
                   let newWindow = controller.window {
                    firstWindow.addTabbedWindowSafely(newWindow, ordered: .above)
                }
            }

            // Make the appropriate window key. If we had a key window, restore it.
            // Otherwise, make the last window key.
            if let keyWindowIndex, keyWindowIndex < controllers.count {
                controllers[keyWindowIndex].window?.makeKeyAndOrderFront(nil)
            } else {
                controllers.last?.window?.makeKeyAndOrderFront(nil)
            }

            // Register redo action on the first controller
            undoManager.registerUndo(
                withTarget: firstController,
                expiresAfter: firstController.undoExpiration
            ) { target in
                target.closeWindowImmediately()
            }
        }
    }

    /// Close all windows, asking for confirmation if necessary.
    static func closeAllWindows() {
        // The window we use for confirmations. Try to find the first window that
        // needs quit confirmation. This lets us attach the confirmation to something
        // that is running.
        guard let confirmWindow = all
            .first(where: { $0.surfaceTree.contains(where: { $0.needsConfirmQuit }) })?
            .surfaceTree.first(where: { $0.needsConfirmQuit })?
            .window
        else {
            closeAllWindowsImmediately()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Close All Windows?"
        alert.informativeText = "All terminal sessions will be terminated."
        alert.addButton(withTitle: "Close All Windows")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.beginSheetModal(for: confirmWindow, completionHandler: { response in
            if response == .alertFirstButtonReturn {
                // This is important so that we avoid losing focus when Stage
                // Manager is used (#8336)
                alert.window.orderOut(nil)
                closeAllWindowsImmediately()
            }
        })
    }

    static private func closeAllWindowsImmediately() {
        let undoManager = (NSApp.delegate as? AppDelegate)?.undoManager
        undoManager?.beginUndoGrouping()
        all.forEach { $0.closeWindowImmediately() }
        undoManager?.setActionName("Close All Windows")
        undoManager?.endUndoGrouping()
    }

    // MARK: Undo/Redo

    /// The state that we require to recreate a TerminalController from an undo.
    struct UndoState {
        let frame: NSRect
        let surfaceTree: SplitTree<Ghostty.SurfaceView>
        let focusedSurface: UUID?
        let tabIndex: Int?
        weak var tabGroup: NSWindowTabGroup?
        let tabColor: TerminalTabColor
    }

    convenience init(_ ghostty: Ghostty.App, with undoState: UndoState) {
        self.init(ghostty, withSurfaceTree: undoState.surfaceTree)

        // Show the window and restore its frame
        showWindow(nil)
        if let window {
            window.setFrame(undoState.frame, display: true)
            if let terminalWindow = window as? TerminalWindow {
                terminalWindow.tabColor = undoState.tabColor
            }

            // If we have a tab group and index, restore the tab to its original position
            if let tabGroup = undoState.tabGroup,
               let tabIndex = undoState.tabIndex {
                if tabIndex < tabGroup.windows.count {
                    // Find the window that is currently at that index
                    let currentWindow = tabGroup.windows[tabIndex]
                    currentWindow.addTabbedWindowSafely(window, ordered: .below)
                } else {
                    tabGroup.windows.last?.addTabbedWindowSafely(window, ordered: .above)
                }

                // Make it the key window
                window.makeKeyAndOrderFront(nil)
            }

            // Restore focus to the previously focused surface
            if let focusedUUID = undoState.focusedSurface,
               let focusTarget = surfaceTree.first(where: { $0.id == focusedUUID }) {
                DispatchQueue.main.async {
                    Ghostty.moveFocus(to: focusTarget, from: nil)
                }
            } else if let focusedSurface = surfaceTree.first {
                // No prior focused surface or we can't find it, let's focus
                // the first.
                self.focusedSurface = focusedSurface
                DispatchQueue.main.async {
                    Ghostty.moveFocus(to: focusedSurface, from: nil)
                }
            }
        }
    }

    /// The current undo state for this controller
    var undoState: UndoState? {
        guard let window else { return nil }
        guard !surfaceTree.isEmpty else { return nil }
        return .init(
            frame: window.frame,
            surfaceTree: surfaceTree,
            focusedSurface: focusedSurface?.id,
            tabIndex: window.tabGroup?.windows.firstIndex(of: window),
            tabGroup: window.tabGroup,
            tabColor: (window as? TerminalWindow)?.tabColor ?? .none)
    }

    // MARK: - NSWindowController

    override func windowWillLoad() {
        // We do NOT want to cascade because we handle this manually from the manager.
        shouldCascadeWindows = false
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        guard let window else { return }
        window.tabbingMode = .disallowed

        // I copy this because we may change the source in the future but also because
        // I regularly audit our codebase for "ghostty.config" access because generally
        // you shouldn't use it. Its safe in this case because for a new window we should
        // use whatever the latest app-level config is.
        let config = ghostty.config

        // Setting all three of these is required for restoration to work.
        window.isRestorable = restorable
        if restorable {
            window.restorationClass = TerminalWindowRestoration.self
            window.identifier = .init(String(describing: TerminalWindowRestoration.self))
        }

        // If we have only a single surface (no splits) and there is a default size then
        // we should resize to that default size.
        if case let .leaf(view) = surfaceTree.root {
            // If this is our first surface then our focused surface will be nil
            // so we force the focused surface to the leaf.
            focusedSurface = view
        }

        // Initialize our content view to the SwiftUI root
        let container = TerminalViewContainer {
            TerminalView(ghostty: ghostty, viewModel: self, delegate: self)
        }
        container.onSidebarWidthChanged = { [weak self] width in
            self?.workspaceSidebarWidth = width
        }

        // Set the initial content size on the container so that
        // intrinsicContentSize returns the correct value immediately,
        // without waiting for @FocusedValue to propagate through the
        // SwiftUI focus chain.
        container.initialContentSize = focusedSurface?.initialSize

        window.contentView = container

        // If we have a default size, we want to apply it.
        if let defaultSize {
            defaultSize.apply(to: window)

            if case .contentIntrinsicSize = defaultSize {
                if let screen = window.screen ?? NSScreen.main {
                    let frame = self.adjustForWindowPosition(frame: window.frame, on: screen)
                    window.setFrameOrigin(frame.origin)
                }
            }
        }

        // In various situations, macOS automatically tabs new windows. Ghostty handles
        // its own tabbing so we DONT want this behavior. This detects this scenario and undoes
        // it.
        //
        // Example scenarios where this happens:
        //   - When the system user tabbing preference is "always"
        //   - When the "+" button in the tab bar is clicked
        //
        // We don't run this logic in fullscreen because in fullscreen this will end up
        // removing the window and putting it into its own dedicated fullscreen, which is not
        // the expected or desired behavior of anyone I've found.
        if !window.styleMask.contains(.fullScreen) {
            // If we have more than 1 window in our tab group we know we're a new window.
            // Since Ghostty manages tabbing manually this will never be more than one
            // at this point in the AppKit lifecycle (we add to the group after this).
            if let tabGroup = window.tabGroup, tabGroup.windows.count > 1 {
                window.tabGroup?.removeWindow(window)
            }
        }

        // Apply any additional appearance-related properties to the new window. We
        // apply this based on the root config but change it later based on surface
        // config (see focused surface change callback).
        syncAppearance(.init(config))
        configureWorkspaceSidebarActions()
        refreshWorkspaceSidebarGroup()
    }

    /// Setup correct window frame before showing the window
    override func showWindow(_ sender: Any?) {
        guard let terminalWindow = window as? TerminalWindow else { return }

        // Set the initial window position. This must happen after the window
        // is fully set up (content view, toolbar, default size) so that
        // decorations added by subclass awakeFromNib (e.g. toolbar for tabs
        // style) don't change the frame after the position is restored.
        let originChanged = terminalWindow.setInitialWindowPosition(
            x: derivedConfig.windowPositionX,
            y: derivedConfig.windowPositionY,
        )
        let restored = LastWindowPosition.shared.restore(
            terminalWindow,
            origin: !originChanged,
            size: defaultSize == nil,
        )

        // If nothing is changed for the frame,
        // we should center the window
        if !originChanged, !restored {
            // This doesn't work in `windowDidLoad` somehow
            terminalWindow.center()
        }

        super.showWindow(sender)
    }

    // Shows the "+" button in the tab bar, responds to that click.
    override func newWindowForTab(_ sender: Any?) {
        _ = Self.newWorkspace(ghostty, from: window)
    }

    // MARK: NSWindowDelegate

    // TabGroupCloseCoordinator.Controller
    lazy private(set) var tabGroupCloseCoordinator = TabGroupCloseCoordinator()

    override func windowShouldClose(_ sender: NSWindow) -> Bool {
        tabGroupCloseCoordinator.windowShouldClose(sender) { [weak self] scope in
            guard let self else { return }
            switch scope {
            case .tab: closeTab(nil)
            case .window:
                guard self.window?.isFirstWindowInTabGroup ?? false else { return }
                closeWindow(nil)
            }
        }

        // We will always explicitly close the window using the above
        return false
    }

    override func windowWillClose(_ notification: Notification) {
        super.windowWillClose(notification)
        self.relabelTabs()

        // If we remove a window, we reset the cascade point to the key window so that
        // the next window cascade's from that one.
        if let focusedWindow = NSApplication.shared.keyWindow {
            // If we are NOT the focused window, then we are a tabbed window. If we
            // are closing a tabbed window, we want to set the cascade point to be
            // the next cascade point from this window.
            if focusedWindow != window {
                // The cascadeTopLeft call below should NOT move the window. Starting with
                // macOS 15, we found that specifically when used with the new window snapping
                // features of macOS 15, this WOULD move the frame. So we keep track of the
                // old frame and restore it if necessary. Issue:
                // https://github.com/ghostty-org/ghostty/issues/2565
                let oldFrame = focusedWindow.frame

                Self.lastCascadePoint = focusedWindow.cascadeTopLeft(from: .zero)

                if focusedWindow.frame != oldFrame {
                    focusedWindow.setFrame(oldFrame, display: true)
                }

                return
            }

            // If we are the focused window, then we set the last cascade point to
            // our own frame so that it shows up in the same spot.
            let frame = focusedWindow.frame
            Self.lastCascadePoint = NSPoint(x: frame.minX, y: frame.maxY)
        }
    }

    override func windowDidBecomeKey(_ notification: Notification) {
        super.windowDidBecomeKey(notification)
        self.relabelTabs()
        self.fixTabBar()
        terminalViewContainer?.updateGlassTintOverlay(isKeyWindow: true)
    }

    override func windowDidResignKey(_ notification: Notification) {
        super.windowDidResignKey(notification)
        terminalViewContainer?.updateGlassTintOverlay(isKeyWindow: false)
    }

    override func windowDidMove(_ notification: Notification) {
        super.windowDidMove(notification)
        self.fixTabBar()

        // Whenever we move save our last position for the next start.
        LastWindowPosition.shared.save(window)
    }

    override func windowDidResize(_ notification: Notification) {
        super.windowDidResize(notification)

        // Whenever we resize save our last position and size for the next start.
        LastWindowPosition.shared.save(window)
    }

    func windowDidBecomeMain(_ notification: Notification) {
        // Whenever we get focused, use that as our last window position for
        // restart. This differs from Terminal.app but matches iTerm2 behavior
        // and I think its sensible.
        LastWindowPosition.shared.save(window)

        // Remember our last main
        Self.lastMain = self
    }

    // Called when the window will be encoded. We handle the data encoding here in the
    // window controller.
    func window(_ window: NSWindow, willEncodeRestorableState state: NSCoder) {
        let data = TerminalRestorableState(from: self)
        data.encode(with: state)
    }

    // MARK: First Responder

    @IBAction func newWindow(_ sender: Any?) {
        _ = Self.newWorkspace(ghostty, from: window)
    }

    @IBAction func newTab(_ sender: Any?) {
        _ = Self.newWindow(ghostty)
    }

    @IBAction func toggleWorkspaceSidebar(_ sender: Any?) {
        workspaceSidebarVisible.toggle()
        refreshWorkspaceSidebar()
    }

    @IBAction func selectPreviousWorkspaceShortcut(_ sender: Any?) {
        selectWorkspace(by: -1)
    }

    @IBAction func selectNextWorkspaceShortcut(_ sender: Any?) {
        selectWorkspace(by: 1)
    }

    @IBAction func moveWorkspaceUpShortcut(_ sender: Any?) {
        moveActiveWorkspace(by: -1)
    }

    @IBAction func moveWorkspaceDownShortcut(_ sender: Any?) {
        moveActiveWorkspace(by: 1)
    }

    @IBAction func closeTab(_ sender: Any?) {
        guard workspaces.count > 1 else {
            closeWindow(sender)
            return
        }

        guard surfaceTree.contains(where: { $0.needsConfirmQuit }) else {
            closeTabImmediately()
            return
        }

        confirmClose(
            messageText: "Close Tab?",
            informativeText: "The terminal still has a running process. If you close the tab the process will be killed."
        ) {
            self.closeTabImmediately()
        }
    }

    @IBAction func closeOtherTabs(_ sender: Any?) {
        guard workspaces.count > 1 else { return }

        syncActiveWorkspaceFromController()
        let otherWorkspaces = workspaces.filter { $0.id != activeWorkspaceID }
        guard !otherWorkspaces.isEmpty else { return }

        guard otherWorkspaces.contains(where: { $0.tree.contains(where: { $0.needsConfirmQuit }) }) else {
            self.closeOtherTabsImmediately()
            return
        }

        confirmClose(
            messageText: "Close Other Tabs?",
            informativeText: "At least one other tab still has a running process. If you close the tab the process will be killed."
        ) {
            self.closeOtherTabsImmediately()
        }
    }

    @IBAction func closeTabsOnTheRight(_ sender: Any?) {
        syncActiveWorkspaceFromController()
        guard let currentIndex = workspaces.firstIndex(where: { $0.id == activeWorkspaceID }) else { return }
        guard currentIndex < workspaces.count - 1 else { return }

        let tabsToClose = Array(workspaces[(currentIndex + 1)...])
        let needsConfirm = tabsToClose.contains { $0.tree.contains(where: { $0.needsConfirmQuit }) }

        if !needsConfirm {
            self.closeTabsOnTheRightImmediately()
            return
        }

        confirmClose(
            messageText: "Close Tabs on the Right?",
            informativeText: "At least one tab to the right still has a running process. If you close the tab the process will be killed."
        ) {
            self.closeTabsOnTheRightImmediately()
        }
    }

    @IBAction func returnToDefaultSize(_ sender: Any?) {
        guard let window, let defaultSize else { return }
        defaultSize.apply(to: window)
    }

    @IBAction override func closeWindow(_ sender: Any?) {
        syncActiveWorkspaceFromController()
        guard workspaces.contains(where: { $0.tree.contains(where: { $0.needsConfirmQuit }) }) else {
            closeWindowImmediately()
            return
        }

        confirmClose(
            messageText: "Close Window?",
            informativeText: "All terminal sessions in this window will be terminated.",
        ) {
            self.closeWindowImmediately()
        }
    }

    @IBAction func toggleGhosttyFullScreen(_ sender: Any?) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.toggleFullscreen(surface: surface)
    }

    @IBAction func toggleTerminalInspector(_ sender: Any?) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.toggleTerminalInspector(surface: surface)
    }

    // MARK: - TerminalViewDelegate

    override func handleLocalKeyDown(_ event: NSEvent) -> Bool {
        guard window?.attachedSheet == nil else { return false }

        let shortcutModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let characters = event.charactersIgnoringModifiers?.lowercased()
        let keyCode = event.keyCode
        let upArrowKeyCode: UInt16 = 126
        let downArrowKeyCode: UInt16 = 125

        if shortcutModifiers == [.command],
           let characters,
           let workspaceNumber = Int(characters),
           (1...9).contains(workspaceNumber) {
            syncActiveWorkspaceFromController()
            let orderedWorkspaces = workspaces
            guard orderedWorkspaces.indices.contains(workspaceNumber - 1) else { return true }
            selectWorkspace(withID: orderedWorkspaces[workspaceNumber - 1].id)
            return true
        }

        if shortcutModifiers == [.command, .option], keyCode == upArrowKeyCode {
            moveActiveWorkspace(by: -1)
            return true
        }

        if shortcutModifiers == [.command, .option], keyCode == downArrowKeyCode {
            moveActiveWorkspace(by: 1)
            return true
        }

        switch (shortcutModifiers, characters) {
        case ([.command], "b"):
            toggleWorkspaceSidebar(nil)
            return true

        case ([.command], "i"):
            makeWorkspaceInactive(id: activeWorkspaceID, referenceDate: .now)
            return true

        case ([.command], "t"):
            _ = Self.newWorkspace(ghostty, from: window)
            return true

        case ([.command, .shift], "n"):
            _ = Self.newWindow(ghostty)
            return true

        default:
            return false
        }
    }

    override func focusedSurfaceDidChange(to: Ghostty.SurfaceView?) {
        super.focusedSurfaceDidChange(to: to)
        if !isApplyingWorkspaceState {
            syncActiveWorkspaceFromController(rebuildObservers: true)
            refreshWorkspaceSidebar()
        }

        // We always cancel our event listener
        surfaceAppearanceCancellables.removeAll()

        // When our focus changes, we update our window appearance based on the
        // currently focused surface.
        guard let focusedSurface else { return }
        syncAppearance(focusedSurface.derivedConfig)

        // We also want to get notified of certain changes to update our appearance.
        focusedSurface.$derivedConfig
            .sink { [weak self, weak focusedSurface] _ in self?.syncAppearanceOnPropertyChange(focusedSurface) }
            .store(in: &surfaceAppearanceCancellables)
        focusedSurface.$backgroundColor
            .sink { [weak self, weak focusedSurface] _ in self?.syncAppearanceOnPropertyChange(focusedSurface) }
            .store(in: &surfaceAppearanceCancellables)
    }

    private func syncAppearanceOnPropertyChange(_ surface: Ghostty.SurfaceView?) {
        guard let surface else { return }
        DispatchQueue.main.async { [weak self, weak surface] in
            guard let surface else { return }
            guard let self else { return }
            guard self.focusedSurface == surface else { return }
            self.syncAppearance(surface.derivedConfig)
        }
    }

    // MARK: - Notifications

    @objc private func onMoveTab(notification: SwiftUI.Notification) {
        guard let target = notification.object as? Ghostty.SurfaceView else { return }
        guard target == self.focusedSurface else { return }

        // Get the move action
        guard let action = notification.userInfo?[Notification.Name.GhosttyMoveTabKey] as? Ghostty.Action.MoveTab else { return }
        guard action.amount != 0 else { return }
        syncActiveWorkspaceFromController()

        var activeWorkspaces = workspaces.filter { !$0.isInactive }
        guard activeWorkspaces.count > 1 else { return }
        guard let selectedIndex = activeWorkspaces.firstIndex(where: { $0.id == activeWorkspaceID }) else { return }

        // Determine the final index we want to insert our tab
        let finalIndex: Int
        if action.amount < 0 {
            finalIndex = selectedIndex - min(selectedIndex, -action.amount)
        } else {
            let remaining = activeWorkspaces.count - 1 - selectedIndex
            finalIndex = selectedIndex + min(remaining, action.amount)
        }

        // If our index is the same we do nothing
        guard finalIndex != selectedIndex else { return }

        let moving = activeWorkspaces.remove(at: selectedIndex)
        activeWorkspaces.insert(moving, at: finalIndex)
        let inactiveWorkspaces = workspaces.filter(\.isInactive)
        workspaces = activeWorkspaces + inactiveWorkspaces
        syncWorkspaceSavedActiveIndices()
        refreshWorkspaceSidebar()
    }

    @objc private func onGotoTab(notification: SwiftUI.Notification) {
        guard let target = notification.object as? Ghostty.SurfaceView else { return }
        guard target == self.focusedSurface else { return }

        // Get the tab index from the notification
        guard let tabEnumAny = notification.userInfo?[Ghostty.Notification.GotoTabKey] else { return }
        guard let tabEnum = tabEnumAny as? ghostty_action_goto_tab_e else { return }
        let tabIndex: Int32 = tabEnum.rawValue
        syncActiveWorkspaceFromController()
        let orderedWorkspaces = workspaces
        guard !orderedWorkspaces.isEmpty else { return }

        // This will be the index we want to actual go to
        let finalIndex: Int

        // An index that is invalid is used to signal some special values.
        if tabIndex <= 0 {
            guard let selectedIndex = orderedWorkspaces.firstIndex(where: { $0.id == activeWorkspaceID }) else { return }

            if tabIndex == GHOSTTY_GOTO_TAB_PREVIOUS.rawValue {
                if selectedIndex == 0 {
                    finalIndex = orderedWorkspaces.count - 1
                } else {
                    finalIndex = selectedIndex - 1
                }
            } else if tabIndex == GHOSTTY_GOTO_TAB_NEXT.rawValue {
                if selectedIndex == orderedWorkspaces.count - 1 {
                    finalIndex = 0
                } else {
                    finalIndex = selectedIndex + 1
                }
            } else if tabIndex == GHOSTTY_GOTO_TAB_LAST.rawValue {
                finalIndex = orderedWorkspaces.count - 1
            } else {
                return
            }
        } else {
            // The configured value is 1-indexed.
            guard tabIndex >= 1 else { return }

            // If our index is outside our boundary then we use the max
            finalIndex = min(Int(tabIndex - 1), orderedWorkspaces.count - 1)
        }

        guard finalIndex >= 0 else { return }
        selectWorkspace(withID: orderedWorkspaces[finalIndex].id)
    }

    @objc private func onCloseTab(notification: SwiftUI.Notification) {
        guard let target = notification.object as? Ghostty.SurfaceView else { return }
        guard surfaceTree.contains(target) else { return }
        closeTab(self)
    }

    @objc private func onCloseOtherTabs(notification: SwiftUI.Notification) {
        guard let target = notification.object as? Ghostty.SurfaceView else { return }
        guard surfaceTree.contains(target) else { return }
        closeOtherTabs(self)
    }

    @objc private func onCloseTabsOnTheRight(notification: SwiftUI.Notification) {
        guard let target = notification.object as? Ghostty.SurfaceView else { return }
        guard surfaceTree.contains(target) else { return }
        closeTabsOnTheRight(self)
    }

    @objc private func onCloseWindow(notification: SwiftUI.Notification) {
        guard let target = notification.object as? Ghostty.SurfaceView else { return }
        guard surfaceTree.contains(target) else { return }
        closeWindow(self)
    }

    @objc private func onResetWindowSize(notification: SwiftUI.Notification) {
        guard let target = notification.object as? Ghostty.SurfaceView else { return }
        guard surfaceTree.contains(target) else { return }
        returnToDefaultSize(nil)
    }

    @objc private func onToggleFullscreen(notification: SwiftUI.Notification) {
        guard let target = notification.object as? Ghostty.SurfaceView else { return }
        guard target == self.focusedSurface else { return }

        // Get the fullscreen mode we want to toggle
        let fullscreenMode: FullscreenMode
        if let any = notification.userInfo?[Ghostty.Notification.FullscreenModeKey],
           let mode = any as? FullscreenMode {
            fullscreenMode = mode
        } else {
            Ghostty.logger.warning("no fullscreen mode specified or invalid mode, doing nothing")
            return
        }

        toggleFullscreen(mode: fullscreenMode)
    }

    struct DerivedConfig {
        let backgroundColor: Color
        let macosWindowButtons: Ghostty.MacOSWindowButtons
        let macosTitlebarStyle: Ghostty.Config.MacOSTitlebarStyle
        let maximize: Bool
        let windowPositionX: Int16?
        let windowPositionY: Int16?

        init() {
            self.backgroundColor = Color(NSColor.windowBackgroundColor)
            self.macosWindowButtons = .visible
            self.macosTitlebarStyle = .default
            self.maximize = false
            self.windowPositionX = nil
            self.windowPositionY = nil
        }

        init(_ config: Ghostty.Config) {
            self.backgroundColor = config.backgroundColor
            self.macosWindowButtons = config.macosWindowButtons
            self.macosTitlebarStyle = config.macosTitlebarStyle
            self.maximize = config.maximize
            self.windowPositionX = config.windowPositionX
            self.windowPositionY = config.windowPositionY
        }
    }
}

// MARK: NSMenuItemValidation

extension TerminalController {
    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(closeTabsOnTheRight):
            guard let currentIndex = workspaces.firstIndex(where: { $0.id == activeWorkspaceID }) else { return false }
            return currentIndex < workspaces.count - 1

        case #selector(returnToDefaultSize):
            guard let window else { return false }

            // Native fullscreen windows can't revert to default size.
            if window.styleMask.contains(.fullScreen) {
                return false
            }

            // If we're fullscreen at all then we can't change size
            if fullscreenStyle?.isFullscreen ?? false {
                return false
            }

            // If our window is already the default size or we don't have a
            // default size, then disable.
            return defaultSize?.isChanged(for: window) ?? false

        default:
            return super.validateMenuItem(item)
        }
    }
}

// MARK: Default Size

extension TerminalController {
    /// The possible default sizes for a terminal. The size can't purely be known as a
    /// window frame because if we set `window-width/height` then it is based
    /// on content size.
    enum DefaultSize {
        /// A frame, set with `window.setFrame`
        case frame(NSRect)

        /// A content size, set with `window.setContentSize`
        case contentIntrinsicSize

        func isChanged(for window: NSWindow) -> Bool {
            switch self {
            case .frame(let rect):
                return window.frame != rect
            case .contentIntrinsicSize:
                guard let view = window.contentView else {
                    return false
                }

                return view.frame.size != view.intrinsicContentSize
            }
        }

        func apply(to window: NSWindow) {
            switch self {
            case .frame(let rect):
                window.setFrame(rect, display: true)
            case .contentIntrinsicSize:
                guard let size = window.contentView?.intrinsicContentSize else {
                    return
                }

                window.setContentSize(size)
                window.constrainToScreen()
            }
        }
    }

    private var defaultSize: DefaultSize? {
        if derivedConfig.maximize, let screen = window?.screen ?? NSScreen.main {
            // Maximize takes priority, we take up the full screen we're on.
            return .frame(screen.visibleFrame)
        } else if focusedSurface?.initialSize != nil {
            // Initial size as requested by the configuration (e.g. `window-width`)
            // takes next priority.
            return .contentIntrinsicSize
        } else {
            return nil
        }
    }
}
