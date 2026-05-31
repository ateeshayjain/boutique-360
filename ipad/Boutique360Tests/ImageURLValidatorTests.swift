import XCTest
@testable import Boutique360

final class ImageURLValidatorTests: XCTestCase {
    func testValidHTTPSURL() {
        if case .success(let url) = ImageURLValidator.validate("https://example.com/dress.jpg") {
            XCTAssertEqual(url.host, "example.com")
        } else { XCTFail("expected success") }
    }
    func testRejectsEmpty() {
        if case .failure(let e) = ImageURLValidator.validate("   ") { XCTAssertEqual(e, .empty) }
        else { XCTFail("expected empty failure") }
    }
    func testRejectsNonHTTP() {
        if case .failure(let e) = ImageURLValidator.validate("ftp://x/y.jpg") { XCTAssertEqual(e, .notHTTP) }
        else { XCTFail("expected notHTTP failure") }
    }
    func testFlagsBlockedHosts() {
        if case .failure(let e) = ImageURLValidator.validate("https://www.instagram.com/p/abc/") {
            XCTAssertEqual(e, .likelyBlockedHost)
        } else { XCTFail("expected likelyBlockedHost") }
    }
}
