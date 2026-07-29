import XCTest
@testable import Boutique360

/// R4b — the PIN is never stored in plaintext (Security §2, §6).
/// Note: constant-time-ness itself is not unit-testable; these tests cover
/// correctness, and the implementation avoids early-exit comparison.
final class PinHasherTests: XCTestCase {
    func testSameSaltAndPinProduceSameDigest() {
        let salt = PinHasher.newSalt()
        XCTAssertEqual(PinHasher.digest(pin: "1357", salt: salt),
                       PinHasher.digest(pin: "1357", salt: salt))
    }

    func testDifferentSaltProducesDifferentDigest() {
        let a = PinHasher.digest(pin: "1357", salt: PinHasher.newSalt())
        let b = PinHasher.digest(pin: "1357", salt: PinHasher.newSalt())
        XCTAssertNotEqual(a, b, "each PIN set must use a fresh salt")
    }

    func testVerifyAcceptsCorrectAndRejectsWrong() {
        let stored = PinHasher.makeStored(pin: "1357")
        XCTAssertTrue(PinHasher.verify(pin: "1357", stored: stored))
        XCTAssertFalse(PinHasher.verify(pin: "1358", stored: stored))
    }

    func testStoredFormatCarriesNoPlaintext() {
        let stored = PinHasher.makeStored(pin: "1357")
        XCTAssertFalse(stored.contains("1357"), "the PIN must never appear in the stored blob")
        XCTAssertTrue(stored.contains(":"), "expected salt:digest")
    }

    func testMalformedStoredBlobFailsClosed() {
        XCTAssertFalse(PinHasher.verify(pin: "1357", stored: "garbage"))
        XCTAssertFalse(PinHasher.verify(pin: "1357", stored: ""))
        XCTAssertFalse(PinHasher.verify(pin: "1357", stored: "notbase64:alsonot"))
    }
}
