import Foundation
import Testing
@testable import Ghostty

struct WorkspaceLastActivityPresentationTests {
    @Test func formatsCompactSidebarTimestamps() {
        #expect(presentedTimestamp(after: 0) == "now")
        #expect(presentedTimestamp(after: 89) == "now")
        #expect(presentedTimestamp(after: 90) == "1m")
        #expect(presentedTimestamp(after: 120) == "2m")
        #expect(presentedTimestamp(after: 1_080) == "18m")
        #expect(presentedTimestamp(after: 7_200) == "2h")
        #expect(presentedTimestamp(after: 86_400) == "1d")
        #expect(presentedTimestamp(after: 691_200) == "1w")
    }

    @Test func clampsFutureDatesToNow() {
        let referenceDate = Date(timeIntervalSince1970: 1_000_000)
        let lastActivityAt = referenceDate.addingTimeInterval(30)

        #expect(
            WorkspaceLastActivityPresentation.sidebarTimestamp(
                lastActivityAt: lastActivityAt,
                referenceDate: referenceDate
            ) == "now"
        )
    }

    private func presentedTimestamp(after elapsed: TimeInterval) -> String {
        let referenceDate = Date(timeIntervalSince1970: 1_000_000)
        let lastActivityAt = referenceDate.addingTimeInterval(-elapsed)
        return WorkspaceLastActivityPresentation.sidebarTimestamp(
            lastActivityAt: lastActivityAt,
            referenceDate: referenceDate
        )
    }
}
