import XCTest
@testable import Boutique360

final class GSTINValidatorTests: XCTestCase {

    func testValidExample() {
        // From the GSTN spec docs: 07AABCS1234A1Z5 (Delhi-state, fake PAN)
        XCTAssertTrue(GSTINValidator.isValid("07AABCS1234A1Z5"))
        XCTAssertNil(GSTINValidator.problem(in: "07AABCS1234A1Z5"))
    }

    func testValidLowercaseGetsUppercasedInternally() {
        // Owner might type in lowercase; validator should still accept by normalizing.
        XCTAssertTrue(GSTINValidator.isValid("07aabcs1234a1z5"))
    }

    func testWhitespaceTrimmed() {
        XCTAssertTrue(GSTINValidator.isValid("  07AABCS1234A1Z5  "))
    }

    func testEmptyIsAllowed() {
        // GSTIN is optional — empty boutique GSTIN is valid (invoices just disabled).
        XCTAssertTrue(GSTINValidator.isValid(""))
        XCTAssertTrue(GSTINValidator.isValid("   "))
    }

    func testWrongLengthRejected() {
        XCTAssertFalse(GSTINValidator.isValid("07AABCS1234A1Z"))     // 14 chars
        XCTAssertFalse(GSTINValidator.isValid("07AABCS1234A1Z55"))   // 16 chars
        XCTAssertNotNil(GSTINValidator.problem(in: "07AABCS1234A1Z"))
    }

    func testStateCodeMustBeDigits() {
        XCTAssertFalse(GSTINValidator.isValid("ABABCS1234A1Z5X"))
    }

    func testPanMiddleMustHaveDigitsAtRightPositions() {
        // The PAN portion is 5 letters + 4 digits + 1 letter.
        XCTAssertFalse(GSTINValidator.isValid("07AABCSXXXXA1Z5"))  // digits replaced with letters
    }

    func testThirteenthCharIsAlphanumeric() {
        XCTAssertTrue(GSTINValidator.isValid("07AABCS1234A1Z5"))    // digit
        XCTAssertTrue(GSTINValidator.isValid("07AABCS1234AAZ5"))    // letter (multiple registrations)
    }

    func testFourteenthCharMustBeZ() {
        XCTAssertFalse(GSTINValidator.isValid("07AABCS1234A1Y5"))   // Y instead of Z
        XCTAssertFalse(GSTINValidator.isValid("07AABCS1234A105"))   // 0 instead of Z
    }

    func testProblemMessageMentionsLength() {
        let problem = GSTINValidator.problem(in: "07AABCS")
        XCTAssertNotNil(problem)
        XCTAssertTrue(problem!.contains("15"), "Length error message should mention expected length")
    }
}
