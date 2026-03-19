import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceSidebarRow: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
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
    var renameSelectedWorkspace: (() -> Void)?
    var newWorkspace: (() -> Void)?

    var activeRows: [WorkspaceSidebarRow] {
        rows.filter { !$0.isInactive }
    }

    func performSelect(_ id: String) {
        selectWorkspace?(id)
    }

    func beginDragging(_ id: String) -> NSItemProvider {
        draggingWorkspaceID = id
        clearDropTarget()
        return NSItemProvider(object: id as NSString)
    }

    func performMove(_ sourceID: String, to insertionIndex: Int) {
        moveWorkspace?(sourceID, insertionIndex)
        clearDragState()
    }

    func performRenameSelectedWorkspace() {
        renameSelectedWorkspace?()
    }

    func performNewWorkspace() {
        newWorkspace?()
    }

    func updateDropInsertionTarget(_ proposedIndex: Int) {
        let clampedIndex = min(max(proposedIndex, 0), activeRows.count)
        let target: WorkspaceSidebarInsertionTarget? = if let draggingWorkspaceID,
            let sourceIndex = activeRows.firstIndex(where: { $0.id == draggingWorkspaceID }),
            WorkspaceSidebarReorderDestination.isNoOp(
                sourceIndex: sourceIndex,
                proposedInsertionIndex: clampedIndex,
                itemCount: activeRows.count
            ) {
            nil
        } else {
            .init(index: clampedIndex)
        }

        guard dropInsertionTarget != target else { return }
        withAnimation(.easeInOut(duration: 0.14)) {
            dropInsertionTarget = target
        }
    }

    func clearDropTarget() {
        guard dropInsertionTarget != nil else { return }
        withAnimation(.easeInOut(duration: 0.14)) {
            dropInsertionTarget = nil
        }
    }

    func clearDragState() {
        draggingWorkspaceID = nil
        clearDropTarget()
    }
}

private enum WorkspaceSidebarDrag {
    static let type = UTType.plainText
}

struct WorkspaceSidebarInsertionTarget: Equatable {
    let index: Int
}

enum WorkspaceSidebarRowDropPosition: Equatable {
    case before
    case after

    static func calculate(at locationY: CGFloat, rowHeight: CGFloat) -> Self {
        guard rowHeight > 0 else { return .before }
        return locationY < (rowHeight / 2) ? .before : .after
    }

    func insertionIndex(forRowAt index: Int) -> Int {
        switch self {
        case .before:
            index
        case .after:
            index + 1
        }
    }
}

enum WorkspaceSidebarReorderDestination {
    static func isNoOp(sourceIndex: Int, proposedInsertionIndex: Int, itemCount: Int) -> Bool {
        let clampedIndex = min(max(proposedInsertionIndex, 0), itemCount)
        return clampedIndex == sourceIndex || clampedIndex == sourceIndex + 1
    }

    static func destinationIndex(
        sourceIndex: Int,
        proposedInsertionIndex: Int,
        itemCount: Int
    ) -> Int? {
        let clampedIndex = min(max(proposedInsertionIndex, 0), itemCount)
        guard !isNoOp(
            sourceIndex: sourceIndex,
            proposedInsertionIndex: clampedIndex,
            itemCount: itemCount
        ) else {
            return nil
        }

        return clampedIndex > sourceIndex ? clampedIndex - 1 : clampedIndex
    }
}

private enum WorkspaceSidebarLayout {
    static let rowSpacing: CGFloat = 8
    static let inactiveTopPadding: CGFloat = 10
    static let inactiveBottomPadding: CGFloat = 12
    static let estimatedRowHeight: CGFloat = 42

    static func estimatedInactiveSectionHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }

        let rowsHeight = CGFloat(rowCount) * estimatedRowHeight
        let spacingHeight = CGFloat(max(0, rowCount - 1)) * rowSpacing
        return inactiveTopPadding + inactiveBottomPadding + rowsHeight + spacingHeight
    }
}

struct WorkspaceSidebarView: View {
    @ObservedObject var viewModel: WorkspaceSidebarViewModel

    private var inactiveRows: [WorkspaceSidebarRow] {
        viewModel.rows.filter(\.isInactive)
    }

    private var inactiveRowsContent: some View {
        VStack(alignment: .leading, spacing: WorkspaceSidebarLayout.rowSpacing) {
            ForEach(inactiveRows) { row in
                WorkspaceSidebarRowView(
                    row: row,
                    theme: viewModel.theme,
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

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if !viewModel.activeRows.isEmpty {
                            ForEach(Array(viewModel.activeRows.enumerated()), id: \.element.id) { index, row in
                                WorkspaceSidebarInsertionIndicator(
                                    isVisible: viewModel.dropInsertionTarget?.index == index,
                                    theme: viewModel.theme
                                )

                                WorkspaceSidebarActiveRow(
                                    row: row,
                                    rowIndex: index,
                                    viewModel: viewModel
                                )
                            }

                            WorkspaceSidebarInsertionIndicator(
                                isVisible: viewModel.dropInsertionTarget?.index == viewModel.activeRows.count,
                                theme: viewModel.theme
                            )
                            WorkspaceSidebarTrailingDropZone(
                                insertionIndex: viewModel.activeRows.count,
                                viewModel: viewModel
                            )
                        } else {
                            WorkspaceSidebarEmptyDropZone(viewModel: viewModel)
                        }
                    }
                    .animation(.easeInOut(duration: 0.14), value: viewModel.dropInsertionTarget)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if !inactiveRows.isEmpty {
                    Group {
                        if estimatedInactiveHeight > maxInactiveHeight {
                            ScrollView {
                                inactiveRowsContent
                            }
                            .frame(maxHeight: maxInactiveHeight)
                        } else {
                            inactiveRowsContent
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .bottomLeading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(viewModel.theme.background)
            .environment(\.colorScheme, viewModel.theme.colorScheme)
        }
    }
}

private struct WorkspaceSidebarActiveRow: View {
    let row: WorkspaceSidebarRow
    let rowIndex: Int

    @ObservedObject var viewModel: WorkspaceSidebarViewModel

    var body: some View {
        WorkspaceSidebarRowView(
            row: row,
            theme: viewModel.theme,
            isDragged: viewModel.draggingWorkspaceID == row.id && viewModel.dropInsertionTarget != nil
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
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onDrop(
                        of: [WorkspaceSidebarDrag.type],
                        delegate: WorkspaceSidebarRowDropDelegate(
                            rowIndex: rowIndex,
                            rowHeight: geometry.size.height,
                            viewModel: viewModel
                        )
                    )
            }
        }
    }
}

private struct WorkspaceSidebarRowView: View {
    let row: WorkspaceSidebarRow
    let theme: WorkspaceSidebarTheme
    var isDragged: Bool = false
    var showsSubtitle: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.system(size: 13, weight: row.isSelected ? .semibold : .medium))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if showsSubtitle, let subtitle = row.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
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
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(backgroundColor)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(opacity)
    }

    private var backgroundColor: Color {
        if row.isSelected {
            return theme.rowSelection.opacity(row.isInactive ? 0.82 : 1.0)
        }

        if row.isInactive {
            return theme.rowInactiveBackground
        }

        return .clear
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

    private var opacity: Double {
        if row.isInactive { return 0.62 }
        return isDragged ? 0.46 : 1.0
    }
}

private struct WorkspaceSidebarInsertionIndicator: View {
    let isVisible: Bool
    let theme: WorkspaceSidebarTheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(theme.rowSelection.opacity(0.94))
                .frame(height: 2)
                .padding(.horizontal, 4)
                .opacity(isVisible ? 1 : 0)
        }
        .frame(height: isVisible ? 14 : 4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WorkspaceSidebarTrailingDropZone: View {
    let insertionIndex: Int
    @ObservedObject var viewModel: WorkspaceSidebarViewModel

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.clear)
            .frame(height: 10)
            .onDrop(
                of: [WorkspaceSidebarDrag.type],
                delegate: WorkspaceSidebarInsertionDropDelegate(
                    insertionIndex: insertionIndex,
                    viewModel: viewModel
                )
            )
    }
}

private struct WorkspaceSidebarEmptyDropZone: View {
    @ObservedObject var viewModel: WorkspaceSidebarViewModel

    var body: some View {
        Color.clear
            .frame(height: 1)
            .onDrop(
                of: [WorkspaceSidebarDrag.type],
                delegate: WorkspaceSidebarInsertionDropDelegate(
                    insertionIndex: 0,
                    viewModel: viewModel
                )
            )
    }
}

private struct WorkspaceSidebarRowDropDelegate: DropDelegate {
    let rowIndex: Int
    let rowHeight: CGFloat
    let viewModel: WorkspaceSidebarViewModel

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [WorkspaceSidebarDrag.type])
    }

    func dropEntered(info: DropInfo) {
        updateDropTarget(for: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropTarget(for: info)
        let operation: DropOperation = viewModel.dropInsertionTarget == nil ? .forbidden : .move
        return DropProposal(operation: operation)
    }

    func dropExited(info: DropInfo) {
        viewModel.clearDropTarget()
    }

    func performDrop(info: DropInfo) -> Bool {
        updateDropTarget(for: info)
        return commitDrop()
    }

    private func updateDropTarget(for info: DropInfo) {
        let position = WorkspaceSidebarRowDropPosition.calculate(
            at: info.location.y,
            rowHeight: rowHeight
        )
        viewModel.updateDropInsertionTarget(position.insertionIndex(forRowAt: rowIndex))
    }

    private func commitDrop() -> Bool {
        guard
            let draggedID = viewModel.draggingWorkspaceID,
            let insertionIndex = viewModel.dropInsertionTarget?.index
        else {
            viewModel.clearDragState()
            return false
        }

        viewModel.performMove(draggedID, to: insertionIndex)
        return true
    }
}

private struct WorkspaceSidebarInsertionDropDelegate: DropDelegate {
    let insertionIndex: Int
    let viewModel: WorkspaceSidebarViewModel

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [WorkspaceSidebarDrag.type])
    }

    func dropEntered(info: DropInfo) {
        viewModel.updateDropInsertionTarget(insertionIndex)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        viewModel.updateDropInsertionTarget(insertionIndex)
        let operation: DropOperation = viewModel.dropInsertionTarget == nil ? .forbidden : .move
        return DropProposal(operation: operation)
    }

    func performDrop(info: DropInfo) -> Bool {
        viewModel.updateDropInsertionTarget(insertionIndex)
        guard
            let draggedID = viewModel.draggingWorkspaceID,
            let targetIndex = viewModel.dropInsertionTarget?.index
        else {
            viewModel.clearDragState()
            return false
        }

        viewModel.performMove(draggedID, to: targetIndex)
        return true
    }

    func dropExited(info: DropInfo) {
        viewModel.clearDropTarget()
    }
}

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
