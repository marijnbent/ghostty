import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceSidebarRow: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let remoteSessionLabel: String?
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
    @Published var theme: WorkspaceSidebarTheme = .default

    var selectWorkspace: ((String) -> Void)?
    var moveWorkspace: ((String, String?) -> Void)?
    var renameSelectedWorkspace: (() -> Void)?
    var newWorkspace: (() -> Void)?

    func performSelect(_ id: String) {
        selectWorkspace?(id)
    }

    func performMove(_ sourceID: String, before targetID: String?) {
        moveWorkspace?(sourceID, targetID)
    }

    func performRenameSelectedWorkspace() {
        renameSelectedWorkspace?()
    }

    func performNewWorkspace() {
        newWorkspace?()
    }
}

private enum WorkspaceSidebarDrag {
    static let type = UTType.plainText
}

struct WorkspaceSidebarView: View {
    @ObservedObject var viewModel: WorkspaceSidebarViewModel

    private var activeRows: [WorkspaceSidebarRow] {
        viewModel.rows.filter { !$0.isInactive }
    }

    private var inactiveRows: [WorkspaceSidebarRow] {
        viewModel.rows.filter(\.isInactive)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(activeRows) { row in
                        WorkspaceSidebarRowView(row: row, theme: viewModel.theme)
                            .onTapGesture {
                                viewModel.performSelect(row.id)
                            }
                            .contextMenu {
                                Button("Rename Workspace…") {
                                    viewModel.performSelect(row.id)
                                    viewModel.performRenameSelectedWorkspace()
                                }
                            }
                            .if(!row.isInactive) { content in
                                content
                                    .onDrag {
                                        viewModel.draggingWorkspaceID = row.id
                                        return NSItemProvider(object: row.id as NSString)
                                    }
                                    .onDrop(
                                        of: [WorkspaceSidebarDrag.type],
                                        delegate: WorkspaceSidebarDropDelegate(
                                            targetID: row.id,
                                            viewModel: viewModel
                                        )
                                    )
                            }
                    }

                    if !activeRows.isEmpty {
                        WorkspaceSidebarDropZone(viewModel: viewModel)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if !inactiveRows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(inactiveRows) { row in
                        WorkspaceSidebarRowView(row: row, theme: viewModel.theme)
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
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(viewModel.theme.background)
        .environment(\.colorScheme, viewModel.theme.colorScheme)
    }
}

private struct WorkspaceSidebarRowView: View {
    let row: WorkspaceSidebarRow
    let theme: WorkspaceSidebarTheme

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.system(size: 13, weight: row.isSelected ? .semibold : .medium))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let subtitle = row.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(subtitleColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
        .opacity(row.isInactive ? 0.62 : 1.0)
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
}

private struct WorkspaceSidebarDropZone: View {
    @ObservedObject var viewModel: WorkspaceSidebarViewModel

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.clear)
            .frame(height: 12)
            .onDrop(
                of: [WorkspaceSidebarDrag.type],
                delegate: WorkspaceSidebarDropDelegate(
                    targetID: nil,
                    viewModel: viewModel
                )
            )
    }
}

private struct WorkspaceSidebarDropDelegate: DropDelegate {
    let targetID: String?
    let viewModel: WorkspaceSidebarViewModel

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [WorkspaceSidebarDrag.type])
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedID = viewModel.draggingWorkspaceID else { return false }
        viewModel.performMove(draggedID, before: targetID)
        viewModel.draggingWorkspaceID = nil
        return true
    }

    func dropExited(info: DropInfo) {
        if !info.hasItemsConforming(to: [WorkspaceSidebarDrag.type]) {
            viewModel.draggingWorkspaceID = nil
        }
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
