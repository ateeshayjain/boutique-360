import XCTest
@testable import Boutique360

final class WhatsAppShareHelperTests: XCTestCase {

    // MARK: - Phone normalization

    func testTenDigitIndianNumberGetsCountryCode() {
        XCTAssertEqual(WhatsAppShareHelper.normalizeIndianPhone("9876543210"), "919876543210")
    }

    func testAlreadyCountryCodedStays() {
        XCTAssertEqual(WhatsAppShareHelper.normalizeIndianPhone("919876543210"), "919876543210")
    }

    func testPlusPrefixStripped() {
        XCTAssertEqual(WhatsAppShareHelper.normalizeIndianPhone("+91 98765 43210"), "919876543210")
    }

    func testHyphenAndSpacesStripped() {
        XCTAssertEqual(WhatsAppShareHelper.normalizeIndianPhone("98765-43210"), "919876543210")
    }

    func testParensStripped() {
        XCTAssertEqual(WhatsAppShareHelper.normalizeIndianPhone("(98765) 43210"), "919876543210")
    }

    func testTooShortReturnsNil() {
        XCTAssertNil(WhatsAppShareHelper.normalizeIndianPhone("12345"))
    }

    func testEmptyReturnsNil() {
        XCTAssertNil(WhatsAppShareHelper.normalizeIndianPhone(""))
        XCTAssertNil(WhatsAppShareHelper.normalizeIndianPhone(nil))
    }

    func testLongerForeignNumberPassesThrough() {
        // 11 digits (e.g., country code 1 + 10-digit US) — keep as-is.
        XCTAssertEqual(WhatsAppShareHelper.normalizeIndianPhone("14155551234"), "14155551234")
    }

    // MARK: - URL building

    func testUrlBuildsWithMessage() {
        let url = WhatsAppShareHelper.url(phone: "9876543210", message: "Hi Priya")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.host, "wa.me")
        XCTAssertEqual(url?.path, "/919876543210")
        XCTAssertEqual(url?.query, "text=Hi%20Priya")
    }

    func testUrlEncodesEmoji() {
        let url = WhatsAppShareHelper.url(phone: "9876543210", message: "Happy birthday 🎉")
        XCTAssertNotNil(url)
        // URLComponents handles percent-encoding of emoji automatically.
        XCTAssertTrue(url!.absoluteString.contains("Happy%20birthday"))
        XCTAssertFalse(url!.absoluteString.contains("🎉"), "Emoji should be percent-encoded in URL")
    }

    func testUrlEncodesNewlines() {
        let url = WhatsAppShareHelper.url(phone: "9876543210", message: "Line 1\nLine 2")
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("Line%201%0ALine%202"))
    }

    func testNilPhoneProducesNilURL() {
        XCTAssertNil(WhatsAppShareHelper.url(phone: nil, message: "hi"))
    }

    func testEmptyPhoneProducesNilURL() {
        XCTAssertNil(WhatsAppShareHelper.url(phone: "", message: "hi"))
    }

    func testHinglishMessageEncodes() {
        let url = WhatsAppShareHelper.url(phone: "9876543210", message: "Namaste! Aapka order ready hai.")
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("Namaste"))
        XCTAssertTrue(url!.absoluteString.contains("Aapka"))
    }
}
