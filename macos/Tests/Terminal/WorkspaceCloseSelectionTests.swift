import Testing
@testable import Ghostty

struct WorkspaceCloseSelectionTests {
    @Test func automaticWorkspaceTitleTrackingStaysEnabledForSinglePaneWorkspaces() {
        #expect(WorkspaceAutomaticTitleTracking.shouldTrackComputedTitle(leafCount: 1))
    }

    @Test func automaticWorkspaceTitleTrackingStopsForSplitWorkspaces() {
        #expect(!WorkspaceAutomaticTitleTracking.shouldTrackComputedTitle(leafCount: 2))
    }

    @Test func closingActiveWorkspacePrefersMostRecentActiveWorkspace() {
        let workspaces: [WorkspaceCloseSelectionEntry] = [
            .init(id: "a", isInactive: false),
            .init(id: "b", isInactive: false),
            .init(id: "c", isInactive: false),
        ]

        let replacement = WorkspaceCloseSelection.replacementID(
            in: workspaces,
            closingID: "c",
            activeWorkspaceID: "c",
            previousWorkspaceID: nil,
            selectionHistory: ["a", "c", "b", "c"]
        )

        #expect(replacement == "b")
    }

    @Test func closingActiveWorkspaceSkipsInactiveHistoryCandidates() {
        let workspaces: [WorkspaceCloseSelectionEntry] = [
            .init(id: "a", isInactive: false),
            .init(id: "b", isInactive: true),
            .init(id: "c", isInactive: false),
        ]

        let replacement = WorkspaceCloseSelection.replacementID(
            in: workspaces,
            closingID: "c",
            activeWorkspaceID: "c",
            previousWorkspaceID: nil,
            selectionHistory: ["a", "b", "c"]
        )

        #expect(replacement == "a")
    }

    @Test func closingActiveWorkspaceFallsBackToLeftNeighborWithoutHistory() {
        let workspaces: [WorkspaceCloseSelectionEntry] = [
            .init(id: "a", isInactive: false),
            .init(id: "b", isInactive: false),
            .init(id: "c", isInactive: false),
        ]

        let replacement = WorkspaceCloseSelection.replacementID(
            in: workspaces,
            closingID: "c",
            activeWorkspaceID: "c",
            previousWorkspaceID: nil,
            selectionHistory: []
        )

        #expect(replacement == "b")
    }

    @Test func closingFirstActiveWorkspaceFallsBackRightWhenNoLeftNeighborExists() {
        let workspaces: [WorkspaceCloseSelectionEntry] = [
            .init(id: "a", isInactive: false),
            .init(id: "b", isInactive: false),
            .init(id: "c", isInactive: false),
        ]

        let replacement = WorkspaceCloseSelection.replacementID(
            in: workspaces,
            closingID: "a",
            activeWorkspaceID: "a",
            previousWorkspaceID: nil,
            selectionHistory: []
        )

        #expect(replacement == "b")
    }

    @Test func closingLastActiveWorkspaceCreatesFreshWorkspaceInsteadOfSelectingInactive() {
        let workspaces: [WorkspaceCloseSelectionEntry] = [
            .init(id: "a", isInactive: false),
            .init(id: "b", isInactive: true),
            .init(id: "c", isInactive: true),
        ]

        let replacement = WorkspaceCloseSelection.replacementID(
            in: workspaces,
            closingID: "a",
            activeWorkspaceID: "a",
            previousWorkspaceID: nil,
            selectionHistory: []
        )

        #expect(replacement == nil)
    }

    @Test func lastActiveWorkspaceCannotBecomeInactive() {
        let workspaces: [WorkspaceCloseSelectionEntry] = [
            .init(id: "a", isInactive: false),
            .init(id: "b", isInactive: true),
            .init(id: "c", isInactive: true),
        ]

        #expect(!WorkspaceInactivityPolicy.canDeactivate(workspaceID: "a", in: workspaces))
    }

    @Test func activeWorkspaceCanBecomeInactiveWhenAnotherActiveWorkspaceExists() {
        let workspaces: [WorkspaceCloseSelectionEntry] = [
            .init(id: "a", isInactive: false),
            .init(id: "b", isInactive: false),
            .init(id: "c", isInactive: true),
        ]

        #expect(WorkspaceInactivityPolicy.canDeactivate(workspaceID: "a", in: workspaces))
        #expect(WorkspaceInactivityPolicy.canDeactivate(workspaceID: "b", in: workspaces))
    }

    @Test func inactiveWorkspaceOnlyReactivatesForExplicitUserInteraction() {
        #expect(WorkspaceInactivityPolicy.shouldReactivateInactiveWorkspace(for: .userInteraction))
        #expect(!WorkspaceInactivityPolicy.shouldReactivateInactiveWorkspace(for: .selection))
        #expect(!WorkspaceInactivityPolicy.shouldReactivateInactiveWorkspace(for: .shellActivity))
    }

    @Test func closingInactiveWorkspaceStillFallsBackToRemainingInactiveWorkspace() {
        let workspaces: [WorkspaceCloseSelectionEntry] = [
            .init(id: "a", isInactive: true),
            .init(id: "b", isInactive: true),
        ]

        let replacement = WorkspaceCloseSelection.replacementID(
            in: workspaces,
            closingID: "a",
            activeWorkspaceID: "a",
            previousWorkspaceID: nil,
            selectionHistory: []
        )

        #expect(replacement == "b")
    }

    @Test func closingActiveWorkspacePrefersImmediatePreviousWorkspaceOverOlderHistory() {
        let workspaces: [WorkspaceCloseSelectionEntry] = [
            .init(id: "a", isInactive: false),
            .init(id: "b", isInactive: false),
            .init(id: "c", isInactive: false),
        ]

        let replacement = WorkspaceCloseSelection.replacementID(
            in: workspaces,
            closingID: "b",
            activeWorkspaceID: "b",
            previousWorkspaceID: "a",
            selectionHistory: ["c", "a"]
        )

        #expect(replacement == "a")
    }

    @Test func recordingSelectionMovesWorkspaceToEndWithoutDuplicates() {
        let history = WorkspaceSelectionHistory.recordingSelection(
            ["a", "b", "c"],
            workspaceID: "b"
        )

        #expect(history == ["a", "c", "b"])
    }

    @Test func pruningHistoryRemovesClosedWorkspaceIDs() {
        let history = WorkspaceSelectionHistory.pruned(
            ["a", "b", "c"],
            validWorkspaceIDs: ["a", "c"]
        )

        #expect(history == ["a", "c"])
    }
}
