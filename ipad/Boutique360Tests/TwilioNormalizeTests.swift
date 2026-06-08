import XCTest
@testable import Boutique360

/// Verifies the phone-normalization rules used before every Twilio SMS.
/// India-first: bare 10-digit + 0-prefixed + 91-prefixed all coerce to
/// E.164. Anything weird returns "" so the caller fails fast rather than
/// shipping a malformed `To` to Twilio (which silently 400s).
final class TwilioNormalizeTests: XCTestCase {

    func testBareIndianMobile() {
        XCTAssertEqual(TwilioClient.normalize("9876543210"), "+919876543210")
    }

    func testWithSpacesAndDashes() {
        XCTAssertEqual(TwilioClient.normalize("98765 43210"), "+919876543210")
        XCTAssertEqual(TwilioClient.normalize("98-76-54-32-10"), "+919876543210")
    }

    func testZeroPrefixed() {
        // STD landline-style prefix that some address books store.
        XCTAssertEqual(TwilioClient.normalize("09876543210"), "+919876543210")
    }

    func testCountryCodePrefixedNoPlus() {
        XCTAssertEqual(TwilioClient.normalize("919876543210"), "+919876543210")
    }

    func testAlreadyE164() {
        XCTAssertEqual(TwilioClient.normalize("+919876543210"), "+919876543210")
    }

    func testForeignE164PreservedNotForcedToIndia() {
        // A US number with + should pass through, not be re-prefixed with +91.
        XCTAssertEqual(TwilioClient.normalize("+12025551234"), "+12025551234")
    }

    func testGarbageRejected() {
        XCTAssertEqual(TwilioClient.normalize(""), "")
        XCTAssertEqual(TwilioClient.normalize("abc"), "")
        XCTAssertEqual(TwilioClient.normalize("12345"), "")     // too short
        XCTAssertEqual(TwilioClient.normalize("00000000000000000"), "")  // weird length
    }
}
