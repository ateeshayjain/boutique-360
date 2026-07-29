import Foundation
import LocalAuthentication
import Security

/// R4b — who is holding the iPad, and how they prove it.
///
/// Scope, stated plainly: this is a **same-device UI boundary, not
/// server-side authorization**. The app holds one Supabase account; anyone
/// with the session token reads everything regardless of role. See
/// `RolePolicy` and SECURITY_REVIEW.md.
///
/// What makes it more than theatre is persistence: role and attempt state
/// live in the Keychain (`…ThisDeviceOnly`, so excluded from backups) and
/// are restored in `init()`. Force-quitting the app does not escape
/// assistant mode and does not clear a lockout.
@MainActor
final class StaffRoleContext: ObservableObject {
    static let shared = StaffRoleContext()

    @Published private(set) var role: StaffRole = .owner
    @Published private(set) var attempts = PinPolicy.AttemptState()

    /// True once an owner PIN exists. Without one, hand-over is meaningless
    /// (there would be no way back), so B4 gates the button on this.
    var hasPin: Bool { storedPin != nil }

    private enum Key {
        static let role = "b360.staff.role"
        static let attempts = "b360.staff.attempts"
        static let pin = "b360.staff.pin"
    }

    /// Keychain items here are `WhenUnlockedThisDeviceOnly` — no iCloud/iTunes
    /// backup copy of the PIN hash or the lockout state (Security §2).
    private static let accessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    private var storedPin: String? { KeychainStore.load(Key.pin) }

    private init() {
        if let raw = KeychainStore.load(Key.role), let r = StaffRole(rawValue: raw) {
            role = r
        }
        if let json = KeychainStore.load(Key.attempts),
           let data = json.data(using: .utf8),
           let state = try? JSONDecoder().decode(PinPolicy.AttemptState.self, from: data) {
            attempts = state
        }
    }

    // MARK: - PIN management

    enum SetPinResult: Equatable {
        case ok
        case invalid(PinPolicy.SetError)
        /// Distinct from `.invalid` so B4 can say "that's not your current
        /// PIN" instead of a grammar complaint about the PIN they typed.
        case wrongCurrent
        case storageFailed
    }

    /// Owner-only (B4 only surfaces this in owner mode).
    func setPin(_ pin: String) -> SetPinResult {
        if let problem = PinPolicy.validate(pin) { return .invalid(problem) }
        guard KeychainStore.save(PinHasher.makeStored(pin: pin),
                                 forKey: Key.pin, accessible: Self.accessible) else {
            return .storageFailed
        }
        // A new PIN also clears any inherited lockout.
        attempts = PinPolicy.cleared()
        persistAttempts()
        audit("staff.pin_set", payload: [:])
        return .ok
    }

    /// Changing requires re-proving the current PIN — otherwise an assistant
    /// who somehow reached the setting could simply overwrite it.
    func changePin(current: String, new: String) -> SetPinResult {
        guard let stored = storedPin, PinHasher.verify(pin: current, stored: stored) else {
            return .wrongCurrent
        }
        return setPin(new)
    }

    // MARK: - Transitions

    enum UnlockResult: Equatable {
        case ok
        case wrong(remaining: Int)
        case cooldown(seconds: Int)
        case capped
        case noPinSet
        case storageFailed
    }

    /// Reducing privilege — no proof required.
    ///
    /// If persistence fails we apply the downgrade **anyway** and tell the
    /// truth about its durability. Refusing here would fail *open*: the iPad
    /// is already being handed across the table.
    @discardableResult
    func handOverToAssistant() -> Bool {
        role = .assistant
        let persisted = KeychainStore.save(StaffRole.assistant.rawValue,
                                           forKey: Key.role, accessible: Self.accessible)
        audit("staff.role_changed", payload: ["from": "owner", "to": "assistant"])
        if !persisted {
            ErrorBus.shared.report(
                "Handed over, but this device will return to owner mode if the app restarts.")
        }
        return persisted
    }

    /// Raising privilege — fails closed. If we can't persist `.owner`, we
    /// don't grant it in memory either, or a restart would silently revoke
    /// access the owner believes they have.
    func unlockToOwner(pin: String) -> UnlockResult {
        switch PinPolicy.lockState(attempts, now: Date()) {
        case .capped: return .capped
        case .cooldown(let seconds): return .cooldown(seconds: seconds)
        case .open: break
        }
        guard let stored = storedPin else { return .noPinSet }

        let correct = PinHasher.verify(pin: pin, stored: stored)
        let next = PinPolicy.afterAttempt(correct: correct, state: attempts, now: Date())

        guard correct else {
            attempts = next
            persistAttempts()
            // No PIN material in the payload, ever.
            audit("staff.unlock_failed",
                  payload: ["failures_since_owner_unlock": String(next.failuresSinceOwnerUnlock)])
            switch PinPolicy.lockState(next, now: Date()) {
            case .capped: return .capped
            case .cooldown(let seconds): return .cooldown(seconds: seconds)
            case .open: return .wrong(remaining: PinPolicy.maxAttempts - next.failures)
            }
        }

        guard KeychainStore.save(StaffRole.owner.rawValue,
                                 forKey: Key.role, accessible: Self.accessible) else {
            return .storageFailed
        }
        role = .owner
        attempts = next
        persistAttempts()
        audit("staff.role_changed", payload: ["from": "assistant", "to": "owner"])
        return .ok
    }

    enum DeviceAuthResult: Equatable { case ok, noPasscodeSet, cancelledOrFailed, storageFailed }

    /// The hard cap's **only** escape (`PinPolicy.hardAttemptCap`). Without
    /// it, 25 wrong taps by an assistant would lock the owner out of their
    /// own till permanently — Keychain state survives even app deletion.
    /// Device-owner auth is the right key here: it proves possession of the
    /// device passcode/biometric, which the assistant does not have.
    func unlockToOwnerWithDeviceAuth() async -> DeviceAuthResult {
        // Held as a local for the whole evaluation — a temporary LAContext can
        // be released mid-flight and the prompt dismisses itself.
        let ctx = LAContext()
        var probeError: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &probeError) else {
            // The UI must name this case specifically: with no device passcode
            // there is no escape at all, and the owner needs to know that
            // before they get capped.
            if (probeError as? LAError)?.code == .passcodeNotSet { return .noPasscodeSet }
            return .cancelledOrFailed
        }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication,
                                                  localizedReason: "Restore owner mode")
            guard ok else { return .cancelledOrFailed }
        } catch {
            return .cancelledOrFailed
        }

        guard KeychainStore.save(StaffRole.owner.rawValue,
                                 forKey: Key.role, accessible: Self.accessible) else {
            return .storageFailed
        }
        role = .owner
        attempts = PinPolicy.cleared()
        persistAttempts()
        audit("staff.unlock_device_auth", payload: [:])
        return .ok
    }

    // MARK: - Private

    private func persistAttempts() {
        guard let data = try? JSONEncoder().encode(attempts),
              let json = String(data: data, encoding: .utf8) else { return }
        KeychainStore.save(json, forKey: Key.attempts, accessible: Self.accessible)
    }

    /// Audit is best-effort: a network failure must not block a role change
    /// the owner is standing there performing.
    private func audit(_ name: String, payload: [String: String]) {
        guard let bid = BoutiqueContext.shared.boutiqueId else { return }
        Task {
            do {
                try await EventsService.record(boutiqueId: bid, eventName: name, payload: payload)
            } catch {
                Log.business.error("audit \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
