import Testing
@testable import Ghostty

struct WorkspaceTitlePresentationTests {
    @Test(arguments: [
        ("marijn@MacBook-Pro-van-Marijn-2:~/Projects/vibescribe", "/Users/marijn/Projects/vibescribe", "vibescribe"),
        ("~/Projects/ghostty", "/Users/marijn/Projects/ghostty", "ghostty"),
        ("~", "/Users/marijn", "Home"),
        ("vim main.swift", "/Users/marijn/Projects/ghostty", "vim main.swift"),
    ])
    func stripsHostAndShortensPaths(
        computedTitle: String,
        location: String?,
        expected: String
    ) {
        #expect(
            WorkspaceTitlePresentation.displayTitle(
                titleOverride: nil,
                computedTitle: computedTitle,
                location: location
            ) == expected
        )
    }

    @Test func preservesBellPrefixWhenSanitizingTitle() {
        #expect(
            WorkspaceTitlePresentation.displayTitle(
                titleOverride: nil,
                computedTitle: "🔔 marijn@MacBook-Pro-van-Marijn-2:~/Projects/vibescribe",
                location: "/Users/marijn/Projects/vibescribe"
            ) == "🔔 vibescribe"
        )
    }

    @Test func titleOverrideWins() {
        #expect(
            WorkspaceTitlePresentation.displayTitle(
                titleOverride: "Client work",
                computedTitle: "marijn@MacBook-Pro-van-Marijn-2:~/Projects/vibescribe",
                location: "/Users/marijn/Projects/vibescribe"
            ) == "Client work"
        )
    }
}
