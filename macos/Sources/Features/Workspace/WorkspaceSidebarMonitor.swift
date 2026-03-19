import Foundation

@MainActor
final class WorkspaceSidebarMonitor {
    static let shared = WorkspaceSidebarMonitor()

    private var timer: Timer?

    private init() {}

    func start() {
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(
            withTimeInterval: 30,
            repeats: true
        ) { _ in
            let now = Date()
            TerminalController.all.forEach { controller in
                controller.evaluateWorkspaceInactivity(referenceDate: now)
            }
        }
    }
}
