import XCTest
@testable import Boutique360

/// R4b — spec Unit 4. The clock-winding and recovery cases are the ones that
/// distinguish a real gate from security theatre.
final class PinPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - validate

    func testLengthBounds() {
        XCTAssertNil(PinPolicy.validate("1357"))
        XCTAssertEqual(PinPolicy.validate("135"), .tooShort)
        XCTAssertEqual(PinPolicy.validate("1357913"), .tooLong)
    }

    func testNonNumericRejected() {
        XCTAssertEqual(PinPolicy.validate("12a4"), .notNumeric)
    }

    func testTooSimpleRejectsIdenticalAndMonotonicRuns() {
        XCTAssertEqual(PinPolicy.validate("0000"), .tooSimple)
        XCTAssertEqual(PinPolicy.validate("111111"), .tooSimple)
        XCTAssertEqual(PinPolicy.validate("1234"), .tooSimple)
        XCTAssertEqual(PinPolicy.validate("4321"), .tooSimple)
        XCTAssertEqual(PinPolicy.validate("456789"), .tooSimple)
    }

    func testNonMonotonicAccepted() {
        // Disambiguates the rule: a strictly monotonic RUN is rejected, not
        // any PIN that happens to contain an adjacent ±1 pair.
        XCTAssertNil(PinPolicy.validate("1235"))
        XCTAssertNil(PinPolicy.validate("112233"))
        XCTAssertNil(PinPolicy.validate("1212"))
    }

    // MARK: - attempt state machine

    func testFourFailuresDoNotLock() {
        var s = PinPolicy.AttemptState()
        for _ in 0..<4 { s = PinPolicy.afterAttempt(correct: false, state: s, now: t0) }
        XCTAssertEqual(PinPolicy.lockState(s, now: t0), .open)
    }

    func testFifthFailureStartsCooldown() {
        var s = PinPolicy.AttemptState()
        for _ in 0..<5 { s = PinPolicy.afterAttempt(correct: false, state: s, now: t0) }
        XCTAssertEqual(PinPolicy.lockState(s, now: t0), .cooldown(secondsRemaining: 30))
    }

    func testCooldownExpires() {
        var s = PinPolicy.AttemptState()
        for _ in 0..<5 { s = PinPolicy.afterAttempt(correct: false, state: s, now: t0) }
        XCTAssertEqual(PinPolicy.lockState(s, now: t0.addingTimeInterval(31)), .open)
    }

    func testAttemptWhileLockedIsNoOp() {
        var s = PinPolicy.AttemptState()
        for _ in 0..<5 { s = PinPolicy.afterAttempt(correct: false, state: s, now: t0) }
        let before = s
        s = PinPolicy.afterAttempt(correct: false, state: s, now: t0.addingTimeInterval(5))
        XCTAssertEqual(s, before, "a wrong tap during cooldown must not extend it")
    }

    func testCorrectAttemptClearsEverything() {
        var s = PinPolicy.AttemptState()
        for _ in 0..<4 { s = PinPolicy.afterAttempt(correct: false, state: s, now: t0) }
        s = PinPolicy.afterAttempt(correct: true, state: s, now: t0)
        XCTAssertEqual(s, PinPolicy.AttemptState())
        XCTAssertEqual(s.failuresSinceOwnerUnlock, 0)
    }

    // MARK: - the clock-winding defence

    func testHardCapSurvivesClockWinding() {
        var s = PinPolicy.AttemptState()
        var now = t0
        for _ in 0..<PinPolicy.hardAttemptCap {
            // Step past each cooldown so every attempt actually lands.
            if case .cooldown = PinPolicy.lockState(s, now: now) { now = now.addingTimeInterval(31) }
            s = PinPolicy.afterAttempt(correct: false, state: s, now: now)
        }
        XCTAssertEqual(s.failuresSinceOwnerUnlock, PinPolicy.hardAttemptCap)
        XCTAssertEqual(PinPolicy.lockState(s, now: now), .capped)
        // Winding the device clock a year forward must NOT clear the cap.
        XCTAssertEqual(PinPolicy.lockState(s, now: now.addingTimeInterval(31_536_000)), .capped)
    }

    func testCappedTakesPrecedenceOverCooldown() {
        var s = PinPolicy.AttemptState()
        s.failuresSinceOwnerUnlock = PinPolicy.hardAttemptCap
        s.lockedUntil = t0.addingTimeInterval(30)
        XCTAssertEqual(PinPolicy.lockState(s, now: t0), .capped)
    }

    func testRecoveryFromCapped() {
        // THE deadlock test: the cap must be escapable, or an assistant can
        // tap 25 wrong PINs and permanently lock the owner out of their own
        // till. This is the pure half of the device-auth recovery path.
        var s = PinPolicy.AttemptState()
        s.failuresSinceOwnerUnlock = PinPolicy.hardAttemptCap
        XCTAssertEqual(PinPolicy.lockState(s, now: t0), .capped)
        s = PinPolicy.cleared()
        XCTAssertEqual(PinPolicy.lockState(s, now: t0), .open)
    }
}
