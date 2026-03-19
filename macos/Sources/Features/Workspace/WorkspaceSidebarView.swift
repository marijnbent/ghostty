import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceSidebarRow: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let shortcutHint: String?
    let remoteSessionLabel: String?
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
        colorScheme: .dark
    )
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
        return inactiveTopPadding + inactiveBottomPadding + rowsHeight + spacingHeight
    }
}

struct WorkspaceSidebarView: View {
    @ObservedObject var viewModel: WorkspaceSidebarViewModel
    @State private var activeRowFrames: [String: CGRect] = [:]

    private var inactiveRows: [WorkspaceSidebarRow] {
        viewModel.rows.filter(\.isInactive)
    }

    private func inactiveRowsContent(sidebarWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: WorkspaceSidebarLayout.rowSpacing) {
            ForEach(inactiveRows) { row in
                WorkspaceSidebarRowView(
                    row: row,
                    theme: viewModel.theme,
                    sidebarWidth: sidebarWidth,
                    showsSubtitle: false
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
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                            pulseScale = 1.22
                        }
                    }
            }

            if let remoteSessionLabel = row.remoteSessionLabel, !remoteSessionLabel.isEmpty {
                Text(remoteSessionLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(0.2)
                    .foregroundStyle(badgeForegroundColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(badgeBackgroundColor)
                    )
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
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .onChange(of: row.hasRunningCommand) { running in
            if !running {
                pulseScale = 1.0
            }
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

    private var showsRunningIndicator: Bool {
        row.hasRunningCommand && (row.remoteSessionLabel == nil || row.remoteSessionLabel?.isEmpty == true)
    }

    private var canShowShortcutHint: Bool {
        isHovered &&
            !isDragged &&
            !showsRunningIndicator &&
            (row.remoteSessionLabel == nil || row.remoteSessionLabel?.isEmpty == true)
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
