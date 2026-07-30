import XCTest
@testable import Boutique360

/// R4b — partial cover for manual QA steps 2 and 4 ("force-quit → still
/// assistant", "force-quit → cooldown still active").
///
/// This exercises the persistence *primitives* StaffRoleContext.init() reads:
/// a `…ThisDeviceOnly` Keychain round-trip plus the AttemptState JSON coding.
/// It does NOT restart the process, so it is not a substitute for the manual
/// steps — it just means a break in the mechanism fails here first.
///
/// Touches the real Keychain (a local system service, no network), and uses
/// its own key namespace so it can't disturb the app's stored role or PIN.
final class RoleStatePersistenceTests: XCTestCase {
    private let key = "b360.test.role.persistence"

    override func tearDown() {
        KeychainStore.delete(key)
        super.tearDown()
    }

    func testRoleSurvivesAKeychainRoundTripThisDeviceOnly() {
        XCTAssertTrue(KeychainStore.save(StaffRole.assistant.rawValue, forKey: key,
                                         accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly))
        XCTAssertEqual(KeychainStore.load(key).flatMap(StaffRole.init(rawValue:)), .assistant)
    }

    func testLockoutStateSurvivesEncodeDecode() throws {
        // A capped state — the one an adversary most wants to lose.
        var state = PinPolicy.AttemptState()
        var now = Date(timeIntervalSince1970: 1_750_000_000)
        for _ in 0..<PinPolicy.hardAttemptCap {
            // `afterAttempt` is a no-op while locked, so the clock has to step
            // past each cooldown or the count stalls at maxAttempts.
            if case .cooldown = PinPolicy.lockState(state, now: now) {
                now = now.addingTimeInterval(31)
            }
            state = PinPolicy.afterAttempt(correct: false, state: state, now: now)
        }
        XCTAssertEqual(state.failuresSinceOwnerUnlock, PinPolicy.hardAttemptCap)
        XCTAssertEqual(PinPolicy.lockState(state, now: now), .capped)

        let json = try XCTUnwrap(String(data: try JSONEncoder().encode(state), encoding: .utf8))
        XCTAssertTrue(KeychainStore.save(json, forKey: key,
                                        accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly))

        let raw = try XCTUnwrap(KeychainStore.load(key))
        let restored = try JSONDecoder().decode(PinPolicy.AttemptState.self,
                                                from: try XCTUnwrap(raw.data(using: .utf8)))
        XCTAssertEqual(restored, state)
        // Evaluated far past every cooldown: only the cap can still be holding.
        XCTAssertEqual(PinPolicy.lockState(restored, now: now.addingTimeInterval(31_536_000)),
                       .capped, "a restored cap must still be a cap")
    }

    func testDeletingTheItemDoesNotSilentlySucceedOnLoad() {
        KeychainStore.save("owner", forKey: key,
                           accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        XCTAssertTrue(KeychainStore.delete(key))
        XCTAssertNil(KeychainStore.load(key))
    }
}
