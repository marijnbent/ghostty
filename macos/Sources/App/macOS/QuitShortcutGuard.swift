import Foundation

struct QuitShortcutGuard {
    enum AttemptResult: Equatable {
        case ignoredRepeat
        case armed
        case confirmed
    }

    let timeout: TimeInterval

    private var armedUntil: TimeInterval?
    private var confirmsNextQuitRequest: Bool = false

    init(timeout: TimeInterval = 1.5) {
        self.timeout = timeout
    }

    mutating func handleShortcutAttempt(
        now: TimeInterval,
        isRepeat: Bool
    ) -> AttemptResult {
        expireIfNeeded(now: now)

        if isRepeat {
            return .ignoredRepeat
        }

        if let armedUntil, now < armedUntil {
            self.armedUntil = nil
            confirmsNextQuitRequest = true
            return .confirmed
        }

        confirmsNextQuitRequest = false
        armedUntil = now + timeout
        return .armed
    }

    mutating func consumeConfirmedQuitRequest(now: TimeInterval) -> Bool {
        expireIfNeeded(now: now)

        guard confirmsNextQuitRequest else { return false }

        confirmsNextQuitRequest = false
        armedUntil = nil
        return true
    }

    mutating func cancel() {
        confirmsNextQuitRequest = false
        armedUntil = nil
    }

    private mutating func expireIfNeeded(now: TimeInterval) {
        guard let armedUntil, now >= armedUntil else { return }

        self.armedUntil = nil
        confirmsNextQuitRequest = false
    }
}
