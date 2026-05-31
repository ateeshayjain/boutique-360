import XCTest
@testable import Boutique360

/// Tests for the RFC 4180-aware CSV escaper used by GSTReportExporter.
/// The escaper is the trickiest correctness-sensitive piece of the export pipeline —
/// a bug here means the CA's GST portal rejects the file or files wrong data.
final class GSTReportExporterTests: XCTestCase {

    func testSimpleStringUnchanged() {
        XCTAssertEqual(GSTReportExporter.csvEscape("Priya Mehta"), "Priya Mehta")
    }

    func testEmptyStringUnchanged() {
        XCTAssertEqual(GSTReportExporter.csvEscape(""), "")
    }

    func testCommaWrappedInQuotes() {
        XCTAssertEqual(GSTReportExporter.csvEscape("Mehta, Priya"), "\"Mehta, Priya\"")
    }

    func testQuoteDoubledAndWrapped() {
        // RFC 4180: embedded " becomes "" and the field is wrapped.
        XCTAssertEqual(GSTReportExporter.csvEscape("Priya \"P\" Mehta"),
                       "\"Priya \"\"P\"\" Mehta\"")
    }

    func testNewlineWrappedInQuotes() {
        XCTAssertEqual(GSTReportExporter.csvEscape("Line 1\nLine 2"), "\"Line 1\nLine 2\"")
    }

    func testCarriageReturnWrappedInQuotes() {
        XCTAssertEqual(GSTReportExporter.csvEscape("a\rb"), "\"a\rb\"")
    }

    func testCombinedSpecialsAllWrapped() {
        XCTAssertEqual(GSTReportExporter.csvEscape("a, \"b\"\nc"),
                       "\"a, \"\"b\"\"\nc\"")
    }

    func testRupeeSignNotConsideredSpecial() {
        // ₹ is multi-byte but not a CSV special. Should pass through.
        XCTAssertEqual(GSTReportExporter.csvEscape("₹1,25,000"), "\"₹1,25,000\"")
        // (Yes, it's wrapped because it contains a comma. That's intentional.)
    }

    func testHindiTextPassesThrough() {
        // No commas/quotes in the Hindi → no wrap needed.
        XCTAssertEqual(GSTReportExporter.csvEscape("नमस्ते"), "नमस्ते")
    }

    func testHinglishWithPunctuation() {
        XCTAssertEqual(GSTReportExporter.csvEscape("Namaste, Priya ji"),
                       "\"Namaste, Priya ji\"")
    }
}
