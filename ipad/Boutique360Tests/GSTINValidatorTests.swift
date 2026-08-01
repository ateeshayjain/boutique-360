import XCTest
@testable import Boutique360

final class GSTINValidatorTests: XCTestCase {

    // 07ABCDE1234F1Z2 — structurally valid AND checksum-valid. The old fixture
    // here (07AABCS1234A1Z5) is structurally fine but its check character is
    // wrong, which is precisely what the checksum now catches.
    private let validGSTIN = "07ABCDE1234F1Z2"

    func testValidExample() {
        XCTAssertTrue(GSTINValidator.isValid(validGSTIN))
        XCTAssertNil(GSTINValidator.problem(in: validGSTIN))
    }

    func testValidLowercaseGetsUppercasedInternally() {
        // Owner might type in lowercase; validator should still accept by normalizing.
        XCTAssertTrue(GSTINValidator.isValid("07abcde1234f1z2"))
    }

    func testWhitespaceTrimmed() {
        XCTAssertTrue(GSTINValidator.isValid("  07ABCDE1234F1Z2  "))
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
        // Both fixtures carry their correct check character — the position-13
        // rule is about structure, but the value must still be a valid GSTIN.
        XCTAssertTrue(GSTINValidator.isValid("07ABCDE1234F1Z2"))    // digit
        XCTAssertTrue(GSTINValidator.isValid("07ABCDE1234FAZT"))    // letter (multiple registrations)
    }

    func testFourteenthCharMustBeZ() {
        // Checksum-correct for its first 14 chars, so this proves the structure
        // rule rejects it rather than the checksum happening to catch it.
        XCTAssertFalse(GSTINValidator.isValid("07ABCDE1234F1Y4"))   // Y instead of Z
        XCTAssertFalse(GSTINValidator.isValid("07AABCS1234A105"))   // 0 instead of Z
    }

    func testProblemMessageMentionsLength() {
        let problem = GSTINValidator.problem(in: "07AABCS")
        XCTAssertNotNil(problem)
        XCTAssertTrue(problem!.contains("15"), "Length error message should mention expected length")
    }

    // MARK: - Checksum (added 2026-08-01)

    /// The reason the checksum exists. This exact value was seeded into the
    /// production boutique by migration 0023 and passed the structure-only
    /// validator, so the app treated it as a real GSTIN and enabled invoicing.
    /// Its check character should be '4', not '5'.
    func testProductionPlaceholderIsRejected() {
        XCTAssertFalse(GSTINValidator.isValid("07AAAAA0000A1Z5"))
        XCTAssertEqual(GSTINValidator.problem(in: "07AAAAA0000A1Z5"),
                       "GSTIN check character doesn't match — re-check the last character")
    }

    func testOtherPlaceholderVariantAlsoRejected() {
        // The variant written in migration 0023's SQL.
        XCTAssertFalse(GSTINValidator.isValid("07AAACA0000A1Z5"))
    }

    func testRealWorldValidGSTINAccepted() {
        // Correct mod-36 check character.
        XCTAssertTrue(GSTINValidator.isValid("27AAPFU0939F1ZV"))
    }

    func testSingleWrongCheckCharacterRejected() {
        var wrong = Array(validGSTIN)
        wrong[14] = wrong[14] == "0" ? "1" : "0"
        XCTAssertFalse(GSTINValidator.isValid(String(wrong)))
    }

    func testStructureErrorsStillReportedBeforeChecksum() {
        // A 14-char string must complain about length, not the check character.
        XCTAssertEqual(GSTINValidator.problem(in: "07ABCDE1234F1Z"),
                       "GSTIN should be 15 characters (got 14)")
    }
}
