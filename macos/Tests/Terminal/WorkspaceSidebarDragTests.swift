import Testing
import CoreGraphics
@testable import Ghostty

struct WorkspaceSidebarDragTests {
    @Test func locationAboveFirstVisibleRowTargetsFrontInsertion() {
        let destination = WorkspaceSidebarInsertionMath.destinationIndex(
            for: 8,
            orderedRowIDs: ["a", "b", "c", "d"],
            draggingID: "b",
            rowFrames: [
                "a": CGRect(x: 0, y: 16, width: 100, height: 24),
                "c": CGRect(x: 0, y: 56, width: 100, height: 24),
                "d": CGRect(x: 0, y: 96, width: 100, height: 24),
            ]
        )
        #expect(destination == 0)
    }

    @Test func locationBetweenVisibleRowsTargetsMiddleInsertion() {
        let destination = WorkspaceSidebarInsertionMath.destinationIndex(
            for: 68,
            orderedRowIDs: ["a", "b", "c", "d"],
            draggingID: "b",
            rowFrames: [
                "a": CGRect(x: 0, y: 16, width: 100, height: 24),
                "c": CGRect(x: 0, y: 56, width: 100, height: 24),
                "d": CGRect(x: 0, y: 96, width: 100, height: 24),
            ]
        )
        #expect(destination == 1)
    }

    @Test func locationBelowLastVisibleRowTargetsEndInsertion() {
        let destination = WorkspaceSidebarInsertionMath.destinationIndex(
            for: 140,
            orderedRowIDs: ["a", "b", "c", "d"],
            draggingID: "b",
            rowFrames: [
                "a": CGRect(x: 0, y: 16, width: 100, height: 24),
                "c": CGRect(x: 0, y: 56, width: 100, height: 24),
                "d": CGRect(x: 0, y: 96, width: 100, height: 24),
            ]
        )
        #expect(destination == 3)
    }

    @Test func singleVisibleGapReturnsSourceIndexWhenAllOtherRowsAreHidden() {
        let destination = WorkspaceSidebarInsertionMath.destinationIndex(
            for: 20,
            orderedRowIDs: ["a"],
            draggingID: "a",
            rowFrames: [:]
        )
        #expect(destination == 0)
    }

    @Test func sameDestinationSlotIsNoOp() {
        let destination = WorkspaceSidebarReorderDestination.destinationIndex(
            sourceIndex: 1,
            proposedDestinationIndex: 1,
            itemCount: 4
        )
        #expect(destination == nil)
    }

    @Test func movingToFrontKeepsFrontDestinationIndex() {
        let destination = WorkspaceSidebarReorderDestination.destinationIndex(
            sourceIndex: 3,
            proposedDestinationIndex: 0,
            itemCount: 4
        )
        #expect(destination == 0)
    }

    @Test func movingDownUsesVisibleDestinationIndex() {
        let destination = WorkspaceSidebarReorderDestination.destinationIndex(
            sourceIndex: 0,
            proposedDestinationIndex: 2,
            itemCount: 4
        )
        #expect(destination == 2)
    }

    @Test func endDestinationMovesItemToEnd() {
        let destination = WorkspaceSidebarReorderDestination.destinationIndex(
            sourceIndex: 1,
            proposedDestinationIndex: 3,
            itemCount: 4
        )
        #expect(destination == 3)
    }

    @Test func singleItemMoveIsNoOp() {
        let destination = WorkspaceSidebarReorderDestination.destinationIndex(
            sourceIndex: 0,
            proposedDestinationIndex: 0,
            itemCount: 1
        )
        #expect(destination == nil)
    }
}
