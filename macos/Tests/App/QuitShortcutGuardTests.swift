import Testing
@testable import Ghostty

@Suite
struct QuitShortcutGuardTests {
    @Test func firstPressArmsQuit() {
        var guardState = QuitShortcutGuard(timeout: 1.5)

        let firstAttempt = guardState.handleShortcutAttempt(now: 10, isRepeat: false)
        let consumed = guardState.consumeConfirmedQuitRequest(now: 10.5)

        #expect(firstAttempt == .armed)
        #expect(!consumed)
    }

    @Test func secondPressWithinTimeoutConfirmsQuit() {
        var guardState = QuitShortcutGuard(timeout: 1.5)

        let firstAttempt = guardState.handleShortcutAttempt(now: 10, isRepeat: false)
        let secondAttempt = guardState.handleShortcutAttempt(now: 11, isRepeat: false)
        let consumed = guardState.consumeConfirmedQuitRequest(now: 11)

        #expect(firstAttempt == .armed)
        #expect(secondAttempt == .confirmed)
        #expect(consumed)
    }

    @Test func secondPressAfterTimeoutRearmsQuit() {
        var guardState = QuitShortcutGuard(timeout: 1.5)

        let firstAttempt = guardState.handleShortcutAttempt(now: 10, isRepeat: false)
        let secondAttempt = guardState.handleShortcutAttempt(now: 11.6, isRepeat: false)
        let consumed = guardState.consumeConfirmedQuitRequest(now: 11.6)

        #expect(firstAttempt == .armed)
        #expect(secondAttempt == .armed)
        #expect(!consumed)
    }

    @Test func repeatedKeydownDoesNotConfirmQuit() {
        var guardState = QuitShortcutGuard(timeout: 1.5)

        let firstAttempt = guardState.handleShortcutAttempt(now: 10, isRepeat: false)
        let repeatedAttempt = guardState.handleShortcutAttempt(now: 10.2, isRepeat: true)
        let consumed = guardState.consumeConfirmedQuitRequest(now: 10.2)

        #expect(firstAttempt == .armed)
        #expect(repeatedAttempt == .ignoredRepeat)
        #expect(!consumed)
    }

    @Test func confirmedQuitRequestIsConsumedOnce() {
        var guardState = QuitShortcutGuard(timeout: 1.5)

        let firstAttempt = guardState.handleShortcutAttempt(now: 10, isRepeat: false)
        let secondAttempt = guardState.handleShortcutAttempt(now: 10.4, isRepeat: false)
        let firstConsume = guardState.consumeConfirmedQuitRequest(now: 10.4)
        let secondConsume = guardState.consumeConfirmedQuitRequest(now: 10.4)

        #expect(firstAttempt == .armed)
        #expect(secondAttempt == .confirmed)
        #expect(firstConsume)
        #expect(!secondConsume)
    }
}
