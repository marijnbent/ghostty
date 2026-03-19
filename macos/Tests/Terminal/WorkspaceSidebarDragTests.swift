import Testing
import CoreGraphics
@testable import Ghostty

struct WorkspaceSidebarDragTests {
    @Test func rowTopHalfTargetsInsertionBeforeRow() {
        let position = WorkspaceSidebarRowDropPosition.calculate(at: 6, rowHeight: 24)
        #expect(position == .before)
        #expect(position.insertionIndex(forRowAt: 2) == 2)
    }

    @Test func rowBottomHalfTargetsInsertionAfterRow() {
        let position = WorkspaceSidebarRowDropPosition.calculate(at: 18, rowHeight: 24)
        #expect(position == .after)
        #expect(position.insertionIndex(forRowAt: 2) == 3)
    }

    @Test func sameInsertionSlotIsNoOp() {
        let destination = WorkspaceSidebarReorderDestination.destinationIndex(
            sourceIndex: 1,
            proposedInsertionIndex: 1,
            itemCount: 4
        )
        #expect(destination == nil)
    }

    @Test func adjacentNextInsertionSlotIsNoOp() {
        let destination = WorkspaceSidebarReorderDestination.destinationIndex(
            sourceIndex: 1,
            proposedInsertionIndex: 2,
            itemCount: 4
        )
        #expect(destination == nil)
    }

    @Test func movingDownAdjustsForRemovedSourceRow() {
        let destination = WorkspaceSidebarReorderDestination.destinationIndex(
            sourceIndex: 0,
            proposedInsertionIndex: 3,
            itemCount: 4
        )
        #expect(destination == 2)
    }

    @Test func movingUpKeepsInsertionIndex() {
        let destination = WorkspaceSidebarReorderDestination.destinationIndex(
            sourceIndex: 3,
            proposedInsertionIndex: 1,
            itemCount: 4
        )
        #expect(destination == 1)
    }

    @Test func endInsertionSlotMovesItemToEnd() {
        let destination = WorkspaceSidebarReorderDestination.destinationIndex(
            sourceIndex: 1,
            proposedInsertionIndex: 4,
            itemCount: 4
        )
        #expect(destination == 3)
    }
}
