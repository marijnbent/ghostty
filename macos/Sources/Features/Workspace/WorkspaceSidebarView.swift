import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum WorkspaceSidebarBadgeTone: Equatable {
    case accent
    case warning
    case success
}

enum WorkspaceSidebarTransientBadge: Equatable {
    case pill(label: String, tone: WorkspaceSidebarBadgeTone)
    case symbol(systemName: String, tone: WorkspaceSidebarBadgeTone)
}

struct WorkspaceSidebarRow: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let shortcutHint: String?
    let lastActivityAt: Date
    let activityTimestamp: String?
    let remoteSessionKind: WorkspaceRemoteSessionKind?
    let agentAttentionLabel: String?
    let transientAttentionBadge: WorkspaceSidebarTransientBadge?
    let unseenAttentionCount: Int
    let hasRunningCommand: Bool
    let isSelected: Bool
    let isInactive: Bool
}

struct WorkspaceSidebarTheme: Equatable {
    let background: Color
    let divider: Color
    let rowSelection: Color
    let rowInactiveBackground: Color
    let title: Color
    let subtitle: Color
    let inactiveTitle: Color
    let inactiveSubtitle: Color
    let badgeBackground: Color
    let badgeForeground: Color
    let warningBadgeBackground: Color
    let warningBadgeForeground: Color
    let successBadgeBackground: Color
    let successBadgeForeground: Color
    let colorScheme: ColorScheme

    static let `default` = Self(
        background: Color(nsColor: .controlBackgroundColor),
        divider: Color(nsColor: .separatorColor),
        rowSelection: Color.accentColor.opacity(0.18),
        rowInactiveBackground: Color.black.opacity(0.04),
        title: .primary,
        subtitle: .secondary,
        inactiveTitle: .secondary,
        inactiveSubtitle: .secondary.opacity(0.9),
        badgeBackground: Color.accentColor.opacity(0.16),
        badgeForeground: Color.accentColor,
        warningBadgeBackground: Color(nsColor: .systemOrange).opacity(0.16),
        warningBadgeForeground: Color(nsColor: .systemOrange),
        successBadgeBackground: Color(nsColor: .systemGreen).opacity(0.16),
        successBadgeForeground: Color(nsColor: .systemGreen),
        colorScheme: .dark
    )
}

private enum WorkspaceSidebarProviderIcon {
    private static let iconSize = NSSize(width: 24, height: 24)
    private static let cachedImages: [WorkspaceRemoteSessionKind: NSImage] = {
        var images: [WorkspaceRemoteSessionKind: NSImage] = [:]
        for kind in [WorkspaceRemoteSessionKind.claude, .codex] {
            if let image = makeImage(for: kind) {
                images[kind] = image
            }
        }
        return images
    }()

    static func image(for kind: WorkspaceRemoteSessionKind) -> NSImage? {
        cachedImages[kind]
    }

    private static func makeImage(for kind: WorkspaceRemoteSessionKind) -> NSImage? {
        let svg: String
        switch kind {
        case .claude:
            svg = """
                <svg height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><title>Claude</title><path d="M4.709 15.955l4.72-2.647.08-.23-.08-.128H9.2l-.79-.048-2.698-.073-2.339-.097-2.266-.122-.571-.121L0 11.784l.055-.352.48-.321.686.06 1.52.103 2.278.158 1.652.097 2.449.255h.389l.055-.157-.134-.098-.103-.097-2.358-1.596-2.552-1.688-1.336-.972-.724-.491-.364-.462-.158-1.008.656-.722.881.06.225.061.893.686 1.908 1.476 2.491 1.833.365.304.145-.103.019-.073-.164-.274-1.355-2.446-1.446-2.49-.644-1.032-.17-.619a2.97 2.97 0 01-.104-.729L6.283.134 6.696 0l.996.134.42.364.62 1.414 1.002 2.229 1.555 3.03.456.898.243.832.091.255h.158V9.01l.128-1.706.237-2.095.23-2.695.08-.76.376-.91.747-.492.584.28.48.685-.067.444-.286 1.851-.559 2.903-.364 1.942h.212l.243-.242.985-1.306 1.652-2.064.73-.82.85-.904.547-.431h1.033l.76 1.129-.34 1.166-1.064 1.347-.881 1.142-1.264 1.7-.79 1.36.073.11.188-.02 2.856-.606 1.543-.28 1.841-.315.833.388.091.395-.328.807-1.969.486-2.309.462-3.439.813-.042.03.049.061 1.549.146.662.036h1.622l3.02.225.79.522.474.638-.079.485-1.215.62-1.64-.389-3.829-.91-1.312-.329h-.182v.11l1.093 1.068 2.006 1.81 2.509 2.33.127.578-.322.455-.34-.049-2.205-1.657-.851-.747-1.926-1.62h-.128v.17l.444.649 2.345 3.521.122 1.08-.17.353-.608.213-.668-.122-1.374-1.925-1.415-2.167-1.143-1.943-.14.08-.674 7.254-.316.37-.729.28-.607-.461-.322-.747.322-1.476.389-1.924.315-1.53.286-1.9.17-.632-.012-.042-.14.018-1.434 1.967-2.18 2.945-1.726 1.845-.414.164-.717-.37.067-.662.401-.589 2.388-3.036 1.44-1.882.93-1.086-.006-.158h-.055L4.132 18.56l-1.13.146-.487-.456.061-.746.231-.243 1.908-1.312-.006.006z" fill="#D97757" fill-rule="nonzero"></path></svg>
                """
        case .codex:
            svg = """
                <svg height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><title>Codex</title><path d="M19.503 0H4.496A4.496 4.496 0 000 4.496v15.007A4.496 4.496 0 004.496 24h15.007A4.496 4.496 0 0024 19.503V4.496A4.496 4.496 0 0019.503 0z" fill="#fff"></path><path d="M9.064 3.344a4.578 4.578 0 012.285-.312c1 .115 1.891.54 2.673 1.275.01.01.024.017.037.021a.09.09 0 00.043 0 4.55 4.55 0 013.046.275l.047.022.116.057a4.581 4.581 0 012.188 2.399c.209.51.313 1.041.315 1.595a4.24 4.24 0 01-.134 1.223.123.123 0 00.03.115c.594.607.988 1.33 1.183 2.17.289 1.425-.007 2.71-.887 3.854l-.136.166a4.548 4.548 0 01-2.201 1.388.123.123 0 00-.081.076c-.191.551-.383 1.023-.74 1.494-.9 1.187-2.222 1.846-3.711 1.838-1.187-.006-2.239-.44-3.157-1.302a.107.107 0 00-.105-.024c-.388.125-.78.143-1.204.138a4.441 4.441 0 01-1.945-.466 4.544 4.544 0 01-1.61-1.335c-.152-.202-.303-.392-.414-.617a5.81 5.81 0 01-.37-.961 4.582 4.582 0 01-.014-2.298.124.124 0 00.006-.056.085.085 0 00-.027-.048 4.467 4.467 0 01-1.034-1.651 3.896 3.896 0 01-.251-1.192 5.189 5.189 0 01.141-1.6c.337-1.112.982-1.985 1.933-2.618.212-.141.413-.251.601-.33.215-.089.43-.164.646-.227a.098.098 0 00.065-.066 4.51 4.51 0 01.829-1.615 4.535 4.535 0 011.837-1.388zm3.482 10.565a.637.637 0 000 1.272h3.636a.637.637 0 100-1.272h-3.636zM8.462 9.23a.637.637 0 00-1.106.631l1.272 2.224-1.266 2.136a.636.636 0 101.095.649l1.454-2.455a.636.636 0 00.005-.64L8.462 9.23z" fill="url(#lobe-icons-codex-fill)"></path><defs><linearGradient gradientUnits="userSpaceOnUse" id="lobe-icons-codex-fill" x1="12" x2="12" y1="3" y2="21"><stop stop-color="#B1A7FF"></stop><stop offset=".5" stop-color="#7A9DFF"></stop><stop offset="1" stop-color="#3941FF"></stop></linearGradient></defs></svg>
                """
        default:
            return nil
        }

        guard let image = NSImage(data: Data(svg.utf8)) else { return nil }
        image.size = iconSize
        image.isTemplate = false
        return image
    }
}

@MainActor
final class WorkspaceSidebarViewModel: ObservableObject {
    @Published var rows: [WorkspaceSidebarRow] = []
    @Published var draggingWorkspaceID: String?
    @Published var dropInsertionTarget: WorkspaceSidebarInsertionTarget?
    @Published var theme: WorkspaceSidebarTheme = .default

    var selectWorkspace: ((String) -> Void)?
    var moveWorkspace: ((String, Int) -> Void)?
    var detachWorkspace: ((String) -> Void)?
    var renameSelectedWorkspace: (() -> Void)?
    var newWorkspace: (() -> Void)?
    private var localDragEndMonitor: Any?
    private var globalDragEndMonitor: Any?
    private var dragCleanupWorkItem: DispatchWorkItem?
    private var isDragInsideActiveList = false

    var activeRows: [WorkspaceSidebarRow] {
        rows.filter { !$0.isInactive }
    }

    var activeDisplayRows: [WorkspaceSidebarRow] {
        let hiddenWorkspaceID: String? = if isDragInsideActiveList {
            draggingWorkspaceID
        } else {
            nil
        }

        guard let hiddenWorkspaceID else { return activeRows }
        return activeRows.filter { $0.id != hiddenWorkspaceID }
    }

    var isDragging: Bool {
        draggingWorkspaceID != nil
    }

    func performSelect(_ id: String) {
        selectWorkspace?(id)
    }

    func beginDragging(_ id: String) -> NSItemProvider {
        draggingWorkspaceID = id
        isDragInsideActiveList = true
        if let sourceIndex = activeRows.firstIndex(where: { $0.id == id }) {
            dropInsertionTarget = .init(index: sourceIndex)
        } else {
            dropInsertionTarget = nil
        }
        installDragEndMonitors()
        return NSItemProvider(object: id as NSString)
    }

    func performMove(_ sourceID: String, to destinationIndex: Int) {
        moveWorkspace?(sourceID, destinationIndex)
        clearDragState()
    }

    func performRenameSelectedWorkspace() {
        renameSelectedWorkspace?()
    }

    func performNewWorkspace() {
        newWorkspace?()
    }

    func updateDropInsertionTarget(_ proposedIndex: Int) {
        let clampedIndex = min(max(proposedIndex, 0), max(activeRows.count - 1, 0))
        let target = WorkspaceSidebarInsertionTarget(index: clampedIndex)
        guard dropInsertionTarget != target else { return }
        dropInsertionTarget = target
    }

    func clearDropTarget() {
        dropInsertionTarget = nil
    }

    func clearDragState() {
        removeDragEndMonitors()
        draggingWorkspaceID = nil
        isDragInsideActiveList = false
        clearDropTarget()
    }

    func setDragInsideActiveList(_ isInside: Bool) {
        guard isDragInsideActiveList != isInside else { return }
        isDragInsideActiveList = isInside
        if !isInside {
            clearDropTarget()
        } else if let draggingWorkspaceID,
            let sourceIndex = activeRows.firstIndex(where: { $0.id == draggingWorkspaceID }),
            dropInsertionTarget == nil {
            dropInsertionTarget = .init(index: sourceIndex)
        }
    }

    private func installDragEndMonitors() {
        guard localDragEndMonitor == nil, globalDragEndMonitor == nil else { return }
        localDragEndMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.scheduleDeferredDragCleanup()
            return event
        }
        globalDragEndMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.scheduleDeferredDragCleanup()
            }
        }
    }

    private func removeDragEndMonitors() {
        dragCleanupWorkItem?.cancel()
        dragCleanupWorkItem = nil
        if let localDragEndMonitor {
            NSEvent.removeMonitor(localDragEndMonitor)
            self.localDragEndMonitor = nil
        }
        if let globalDragEndMonitor {
            NSEvent.removeMonitor(globalDragEndMonitor)
            self.globalDragEndMonitor = nil
        }
    }

    private func scheduleDeferredDragCleanup() {
        dragCleanupWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.draggingWorkspaceID != nil else { return }
            self.clearDragState()
        }
        dragCleanupWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }
}

private enum WorkspaceSidebarDrag {
    static let type = UTType.plainText
}

struct WorkspaceSidebarInsertionTarget: Equatable {
    let index: Int
}

enum WorkspaceSidebarInsertionMath {
    static func destinationIndex(
        for locationY: CGFloat,
        orderedRowIDs: [String],
        draggingID: String?,
        rowFrames: [String: CGRect]
    ) -> Int? {
        guard draggingID != nil else { return nil }

        let visibleRowIDs = orderedRowIDs.filter { $0 != draggingID }
        guard !visibleRowIDs.isEmpty else { return 0 }

        let orderedFrames = visibleRowIDs.compactMap { rowFrames[$0] }
        guard orderedFrames.count == visibleRowIDs.count else { return nil }

        for (index, frame) in orderedFrames.enumerated() where locationY <= frame.midY {
            return index
        }

        return orderedFrames.count
    }
}

enum WorkspaceSidebarReorderDestination {
    static func isNoOp(sourceIndex: Int, proposedDestinationIndex: Int, itemCount: Int) -> Bool {
        guard itemCount > 1 else { return true }
        let clampedIndex = min(max(proposedDestinationIndex, 0), itemCount - 1)
        return clampedIndex == sourceIndex
    }

    static func destinationIndex(
        sourceIndex: Int,
        proposedDestinationIndex: Int,
        itemCount: Int
    ) -> Int? {
        guard itemCount > 1 else { return nil }
        let clampedIndex = min(max(proposedDestinationIndex, 0), itemCount - 1)
        guard !isNoOp(
            sourceIndex: sourceIndex,
            proposedDestinationIndex: clampedIndex,
            itemCount: itemCount
        ) else {
            return nil
        }

        return clampedIndex
    }
}

private enum WorkspaceSidebarLayout {
    static let rowSpacing: CGFloat = 8
    static let dropPlaceholderHeight: CGFloat = 28
    static let bottomDropAreaHeight: CGFloat = dropPlaceholderHeight * 3
    static let inactiveTopPadding: CGFloat = 10
    static let inactiveBottomPadding: CGFloat = 12
    static let estimatedRowHeight: CGFloat = 38
    static let dragAnimation = Animation.spring(response: 0.2, dampingFraction: 0.85)
    static let coordinateSpaceName = "WorkspaceSidebarActiveList"

    static func estimatedInactiveSectionHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }

        let rowsHeight = CGFloat(rowCount) * estimatedRowHeight
        let spacingHeight = CGFloat(max(0, rowCount - 1)) * rowSpacing
        return inactiveTopPadding +
            inactiveBottomPadding +
            rowsHeight +
            spacingHeight
    }
}

struct WorkspaceSidebarView: View {
    @ObservedObject var viewModel: WorkspaceSidebarViewModel
    @State private var activeRowFrames: [String: CGRect] = [:]

    private var inactiveRows: [WorkspaceSidebarRow] {
        viewModel.rows
            .filter(\.isInactive)
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    private func inactiveRowsContent(sidebarWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: WorkspaceSidebarLayout.rowSpacing) {
            ForEach(inactiveRows) { row in
                WorkspaceSidebarRowView(
                    row: row,
                    theme: viewModel.theme,
                    sidebarWidth: sidebarWidth
                )
                .onTapGesture {
                    viewModel.performSelect(row.id)
                }
                .contextMenu {
                    Button("Rename Workspace…") {
                        viewModel.performSelect(row.id)
                        viewModel.performRenameSelectedWorkspace()
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, WorkspaceSidebarLayout.inactiveTopPadding)
        .padding(.bottom, WorkspaceSidebarLayout.inactiveBottomPadding)
    }

    var body: some View {
        GeometryReader { geometry in
            let maxInactiveHeight = geometry.size.height / 3
            let estimatedInactiveHeight = WorkspaceSidebarLayout.estimatedInactiveSectionHeight(
                rowCount: inactiveRows.count
            )
            let sidebarWidth = geometry.size.width

            VStack(spacing: 0) {
                GeometryReader { activeArea in
                    ScrollView {
                        WorkspaceSidebarActiveList(
                            viewModel: viewModel,
                            activeRowFrames: $activeRowFrames,
                            sidebarWidth: sidebarWidth
                        )
                        .frame(
                            minHeight: max(activeArea.size.height - 20, 1),
                            alignment: .topLeading
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                }
                .onChange(of: viewModel.draggingWorkspaceID) { draggingWorkspaceID in
                    if draggingWorkspaceID == nil {
                        viewModel.clearDropTarget()
                        activeRowFrames = [:]
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if !inactiveRows.isEmpty {
                    Group {
                        if estimatedInactiveHeight > maxInactiveHeight {
                            ScrollView {
                                inactiveRowsContent(sidebarWidth: sidebarWidth)
                            }
                            .frame(maxHeight: maxInactiveHeight)
                        } else {
                            inactiveRowsContent(sidebarWidth: sidebarWidth)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .bottomLeading)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: inactiveRows.isEmpty)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(viewModel.theme.background)
            .environment(\.colorScheme, viewModel.theme.colorScheme)
        }
    }
}

private struct WorkspaceSidebarActiveList: View {
    @ObservedObject var viewModel: WorkspaceSidebarViewModel
    @Binding var activeRowFrames: [String: CGRect]
    let sidebarWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: WorkspaceSidebarLayout.rowSpacing) {
            if !viewModel.activeRows.isEmpty {
                ForEach(Array(viewModel.activeDisplayRows.enumerated()), id: \.element.id) { index, row in
                    if viewModel.dropInsertionTarget?.index == index, viewModel.isDragging {
                        WorkspaceSidebarDropPlaceholder(theme: viewModel.theme)
                    }

                    WorkspaceSidebarActiveRow(
                        row: row,
                        viewModel: viewModel,
                        sidebarWidth: sidebarWidth
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
                    ))
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: WorkspaceSidebarRowFramePreferenceKey.self,
                                    value: [row.id: geometry.frame(in: .named(WorkspaceSidebarLayout.coordinateSpaceName))]
                                )
                            }
                        }
                }

                if viewModel.dropInsertionTarget?.index == viewModel.activeDisplayRows.count, viewModel.isDragging {
                    WorkspaceSidebarDropPlaceholder(theme: viewModel.theme)
                }

                Color.clear
                    .frame(height: viewModel.isDragging ? WorkspaceSidebarLayout.bottomDropAreaHeight : 0)
            } else {
                Color.clear.frame(height: 1)
            }
        }
        .coordinateSpace(name: WorkspaceSidebarLayout.coordinateSpaceName)
        .onPreferenceChange(WorkspaceSidebarRowFramePreferenceKey.self) { activeRowFrames = $0 }
        .onDrop(
            of: [WorkspaceSidebarDrag.type],
            delegate: WorkspaceSidebarListDropDelegate(
                viewModel: viewModel,
                rowFrames: { activeRowFrames }
            )
        )
        .animation(WorkspaceSidebarLayout.dragAnimation, value: viewModel.draggingWorkspaceID)
        .animation(WorkspaceSidebarLayout.dragAnimation, value: viewModel.dropInsertionTarget)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: viewModel.activeDisplayRows.map(\.id))
    }
}

private struct WorkspaceSidebarActiveRow: View {
    let row: WorkspaceSidebarRow

    @ObservedObject var viewModel: WorkspaceSidebarViewModel
    let sidebarWidth: CGFloat

    var body: some View {
        WorkspaceSidebarRowView(
            row: row,
            theme: viewModel.theme,
            sidebarWidth: sidebarWidth
        )
        .onTapGesture {
            viewModel.performSelect(row.id)
        }
        .contextMenu {
            Button("Rename Workspace…") {
                viewModel.performSelect(row.id)
                viewModel.performRenameSelectedWorkspace()
            }
        }
        .onDrag {
            viewModel.beginDragging(row.id)
        } preview: {
            WorkspaceSidebarRowView(
                row: row,
                theme: viewModel.theme,
                isDragged: true
            )
            .frame(width: 220)
        }
    }
}

private struct WorkspaceSidebarRowView: View {
    let row: WorkspaceSidebarRow
    let theme: WorkspaceSidebarTheme
    var sidebarWidth: CGFloat = 248
    var isDragged: Bool = false
    var showsSubtitle: Bool = true
    @State private var pulseScale: Double = 1.0
    @State private var isHovered: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.system(size: 13, weight: row.isSelected ? .semibold : .medium))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if showsSubtitle, let displaySubtitle, !displaySubtitle.isEmpty {
                    Text(displaySubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(subtitleColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsRunningIndicator {
                Circle()
                    .fill(badgeForegroundColor)
                    .frame(width: 8, height: 8)
                    .fixedSize()
                    .scaleEffect(pulseScale)
            }

            if let remoteSessionKind = row.remoteSessionKind {
                remoteSessionBadge(remoteSessionKind)
            }

            if let agentAttentionLabel = row.agentAttentionLabel, !agentAttentionLabel.isEmpty {
                badgePill(agentAttentionLabel, tone: .warning)
            }

            if let transientAttentionBadge = row.transientAttentionBadge {
                transientBadgeView(transientAttentionBadge)
            }

            if row.unseenAttentionCount > 0 {
                Text("\(row.unseenAttentionCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(toneForegroundColor(.warning))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(toneBackgroundColor(.warning))
                    )
                    .lineLimit(1)
                    .fixedSize()
            }

            if let activityTimestamp = row.activityTimestamp, !activityTimestamp.isEmpty {
                Text(activityTimestamp)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(activityTimestampColor)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(backgroundColor)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(dragOutlineColor, lineWidth: isDragged ? 1.5 : 0)
        }
        .overlay(alignment: .trailing) {
            if canShowShortcutHint, let shortcutHint = row.shortcutHint {
                Text(shortcutHint)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.subtitle.opacity(0.65))
                    .padding(.trailing, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)))
            }
        }
        .animation(.easeInOut(duration: 0.14), value: canShowShortcutHint)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(
            color: isDragged ? theme.rowSelection.opacity(0.24) : .clear,
            radius: isDragged ? 10 : 0,
            x: 0,
            y: isDragged ? 4 : 0
        )
        .scaleEffect(isDragged ? 0.985 : (isHovered ? 1.012 : 1.0))
        .opacity(opacity)
        .animation(.easeInOut(duration: 0.18), value: row.isSelected)
        .onAppear {
            updatePulseAnimation(isRunning: row.hasRunningCommand)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .onChange(of: row.hasRunningCommand) { running in
            updatePulseAnimation(isRunning: running)
        }
    }

    private var backgroundColor: Color {
        if isDragged {
            return theme.rowSelection.opacity(row.isInactive ? 0.58 : 0.72)
        }

        if row.isSelected {
            return theme.rowSelection.opacity(row.isInactive ? 0.82 : 1.0)
        }

        if row.isInactive {
            return theme.rowInactiveBackground
        }

        return .clear
    }

    private var dragOutlineColor: Color {
        guard isDragged else { return .clear }
        return theme.rowSelection.opacity(0.95)
    }

    private var titleColor: Color {
        if row.isSelected {
            return theme.title
        }

        return row.isInactive ? theme.inactiveTitle : theme.title
    }

    private var subtitleColor: Color {
        row.isInactive ? theme.inactiveSubtitle : theme.subtitle
    }

    private var badgeBackgroundColor: Color {
        row.isInactive ? theme.badgeBackground.opacity(0.72) : theme.badgeBackground
    }

    private var badgeForegroundColor: Color {
        row.isInactive ? theme.badgeForeground.opacity(0.78) : theme.badgeForeground
    }

    private func badgePill(_ label: String, tone: WorkspaceSidebarBadgeTone) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .kerning(0.2)
            .foregroundStyle(toneForegroundColor(tone))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(toneBackgroundColor(tone))
            )
            .lineLimit(1)
            .fixedSize()
    }

    @ViewBuilder
    private func remoteSessionBadge(_ kind: WorkspaceRemoteSessionKind) -> some View {
        if kind.usesSidebarIcon, let image = WorkspaceSidebarProviderIcon.image(for: kind) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
                .fixedSize()
                .accessibilityLabel(kind.badgeLabel)
        } else {
            badgePill(kind.badgeLabel, tone: .accent)
        }
    }

    @ViewBuilder
    private func transientBadgeView(_ badge: WorkspaceSidebarTransientBadge) -> some View {
        switch badge {
        case .pill(let label, let tone):
            badgePill(label, tone: tone)
        case .symbol(let systemName, let tone):
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(toneForegroundColor(tone))
                .frame(width: 16, height: 16)
        }
    }

    private func toneBackgroundColor(_ tone: WorkspaceSidebarBadgeTone) -> Color {
        let color: Color = switch tone {
        case .accent:
            badgeBackgroundColor
        case .warning:
            row.isInactive ? theme.warningBadgeBackground.opacity(0.72) : theme.warningBadgeBackground
        case .success:
            row.isInactive ? theme.successBadgeBackground.opacity(0.72) : theme.successBadgeBackground
        }
        return color
    }

    private func toneForegroundColor(_ tone: WorkspaceSidebarBadgeTone) -> Color {
        let color: Color = switch tone {
        case .accent:
            badgeForegroundColor
        case .warning:
            row.isInactive ? theme.warningBadgeForeground.opacity(0.78) : theme.warningBadgeForeground
        case .success:
            row.isInactive ? theme.successBadgeForeground.opacity(0.78) : theme.successBadgeForeground
        }
        return color
    }

    private var activityTimestampColor: Color {
        if row.isSelected {
            return theme.title.opacity(0.72)
        }

        return row.isInactive ? theme.inactiveSubtitle : theme.subtitle.opacity(0.72)
    }

    private var showsRunningIndicator: Bool {
        row.hasRunningCommand && (row.remoteSessionKind?.usesSidebarIcon != true)
    }

    private var canShowShortcutHint: Bool {
        isHovered &&
            !isDragged &&
            !showsRunningIndicator &&
            (row.agentAttentionLabel == nil || row.agentAttentionLabel?.isEmpty == true) &&
            row.transientAttentionBadge == nil &&
            row.unseenAttentionCount == 0 &&
            (row.activityTimestamp == nil || row.activityTimestamp?.isEmpty == true) &&
            row.remoteSessionKind == nil
    }

    private var displaySubtitle: String? {
        guard let subtitle = row.subtitle, !subtitle.isEmpty else { return nil }
        guard sidebarWidth < 190 else { return subtitle }

        let lastPathComponent = (subtitle as NSString).lastPathComponent
        return lastPathComponent.isEmpty ? subtitle : lastPathComponent
    }

    private var opacity: Double {
        if row.isInactive { return 0.62 }
        return isDragged ? 0.82 : 1.0
    }

    private func updatePulseAnimation(isRunning: Bool) {
        guard isRunning else {
            pulseScale = 1.0
            return
        }

        pulseScale = 1.0
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
            pulseScale = 1.22
        }
    }
}

private struct WorkspaceSidebarDropPlaceholder: View {
    let theme: WorkspaceSidebarTheme

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(theme.rowSelection.opacity(0.14))
            .overlay(alignment: .center) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(theme.rowSelection.opacity(0.96))
                    .frame(height: 3)
                    .padding(.horizontal, 4)
            }
            .frame(height: WorkspaceSidebarLayout.dropPlaceholderHeight)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .accessibilityHidden(true)
    }
}

private struct WorkspaceSidebarRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct WorkspaceSidebarListDropDelegate: DropDelegate {
    let viewModel: WorkspaceSidebarViewModel
    let rowFrames: () -> [String: CGRect]

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [WorkspaceSidebarDrag.type])
    }

    func dropEntered(info: DropInfo) {
        viewModel.setDragInsideActiveList(true)
        updateDropTarget(for: info)
    }

    func dropExited(info: DropInfo) {
        viewModel.setDragInsideActiveList(false)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        viewModel.setDragInsideActiveList(true)
        updateDropTarget(for: info)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        viewModel.setDragInsideActiveList(true)
        updateDropTarget(for: info)
        return commitDrop()
    }

    private func updateDropTarget(for info: DropInfo) {
        guard let destinationIndex = WorkspaceSidebarInsertionMath.destinationIndex(
            for: info.location.y,
            orderedRowIDs: viewModel.activeRows.map(\.id),
            draggingID: viewModel.draggingWorkspaceID,
            rowFrames: rowFrames()
        ) else {
            return
        }
        viewModel.updateDropInsertionTarget(destinationIndex)
    }

    private func commitDrop() -> Bool {
        guard
            let draggedID = viewModel.draggingWorkspaceID,
            let destinationIndex = viewModel.dropInsertionTarget?.index
        else {
            viewModel.clearDragState()
            return false
        }

        viewModel.performMove(draggedID, to: destinationIndex)
        return true
    }
}

private extension CGRect {
    var midY: CGFloat {
        minY + (height / 2)
    }
}
