import Foundation

/// Who is holding the iPad right now. Defaults to `.owner`; the owner hands
/// over explicitly, and only a correct PIN or device-owner auth comes back.
enum StaffRole: String, Codable { case owner, assistant }

/// R4b — pure PIN validation + the failed-attempt state machine.
/// Spec: docs/superpowers/specs/2026-07-28-reminders-roles-design.md Unit 4.
///
/// Two rules exist for reasons worth keeping in view:
/// 1. **`.capped` is clock-independent.** `lockedUntil` is wall-clock, and an
///    assistant on a shared iPad can wind the device clock forward in iOS
///    Settings to clear a timed lockout. The cap is the real defence.
/// 2. **The cap's escape is device-owner auth, never another PIN attempt.**
///    A cap with no escape would let an assistant tap 25 wrong PINs and lock
///    the owner out of their own till permanently — Keychain state survives
///    even app deletion. That trades confidentiality for an
///    adversary-triggerable outage.
enum PinPolicy {
    static let minLength = 4
    static let maxLength = 6
    static let maxAttempts = 5
    static let lockoutSeconds: TimeInterval = 30

    /// Reaching this many failures since the last successful owner unlock
    /// stops accepting PIN attempts entirely. Escape: `StaffRoleContext
    /// .unlockToOwnerWithDeviceAuth()`.
    static let hardAttemptCap = 25

    enum SetError: Equatable { case tooShort, tooLong, notNumeric, tooSimple }

    /// Security §6 weak-credential rule. `tooSimple` rejects a PIN that is
    /// EITHER all-identical digits (0000, 111111) OR a strictly monotonic run
    /// — every step +1 (1234, 456789) or every step −1 (4321).
    /// Anything else passes: 1235 ✓, 112233 ✓, 1357 ✓, 1212 ✓.
    static func validate(_ pin: String) -> SetError? {
        guard pin.allSatisfy(\.isNumber) else { return .notNumeric }
        guard pin.count >= minLength else { return .tooShort }
        guard pin.count <= maxLength else { return .tooLong }

        let digits = pin.compactMap { $0.wholeNumberValue }
        guard digits.count == pin.count else { return .notNumeric }

        let steps = zip(digits, digits.dropFirst()).map { $1 - $0 }
        if steps.allSatisfy({ $0 == 0 }) { return .tooSimple }   // all identical
        if steps.allSatisfy({ $0 == 1 }) { return .tooSimple }   // ascending run
        if steps.allSatisfy({ $0 == -1 }) { return .tooSimple }  // descending run
        return nil
    }

    struct AttemptState: Equatable, Codable {
        var failures: Int = 0
        var lockedUntil: Date?
        /// Monotonic across lockouts. Reset ONLY by a correct PIN or by
        /// device-owner re-auth — this is what the winding clock can't touch.
        var failuresSinceOwnerUnlock: Int = 0
    }

    /// Two distinct locked states, because only one has a countdown and the
    /// UI must not render a phantom timer for the other (Content §3).
    enum LockState: Equatable {
        case open
        case cooldown(secondsRemaining: Int)
        case capped
    }

    /// `.capped` is checked FIRST — it outranks any timed cooldown.
    static func lockState(_ state: AttemptState, now: Date) -> LockState {
        if state.failuresSinceOwnerUnlock >= hardAttemptCap { return .capped }
        if let until = state.lockedUntil, until > now {
            // Round up so the countdown never under-promises.
            return .cooldown(secondsRemaining: Int(ceil(until.timeIntervalSince(now))))
        }
        return .open
    }

    static func isLocked(_ state: AttemptState, now: Date) -> Bool {
        lockState(state, now: now) != .open
    }

    /// Clears failures AND the cap. Called only after a correct PIN or a
    /// successful device-owner re-auth.
    static func cleared() -> AttemptState { AttemptState() }

    /// While locked, an attempt is a NO-OP: state unchanged, cooldown not
    /// extended (a wrong tap during cooldown shouldn't restart the clock —
    /// the caller refuses the attempt anyway).
    static func afterAttempt(correct: Bool, state: AttemptState, now: Date) -> AttemptState {
        guard !isLocked(state, now: now) else { return state }
        if correct { return cleared() }

        var next = state
        next.failures += 1
        next.failuresSinceOwnerUnlock += 1
        if next.failures >= maxAttempts {
            next.lockedUntil = now.addingTimeInterval(lockoutSeconds)
            next.failures = 0          // the cap counter deliberately keeps climbing
        }
        return next
    }
}
