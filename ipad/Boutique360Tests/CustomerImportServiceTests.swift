import XCTest
@testable import Boutique360

/// Pure parser tests — no network. The `parse(csv:)` function should handle
/// RFC 4180 edge cases (quoted commas, escaped quotes, CRLF/LF, embedded newlines).
final class CustomerImportServiceTests: XCTestCase {

    func testSimpleCSVOneRow() {
        let csv = """
        name,phone,email
        Priya Mehta,9876543210,priya@example.com
        """
        let report = CustomerImportService.parse(csv: csv)
        XCTAssertEqual(report.parsed.count, 1)
        XCTAssertEqual(report.skipped.count, 0)
        XCTAssertEqual(report.parsed[0].name, "Priya Mehta")
        XCTAssertEqual(report.parsed[0].phone, "9876543210")
        XCTAssertEqual(report.parsed[0].email, "priya@example.com")
    }

    func testHeaderMatchingIsCaseInsensitive() {
        let csv = """
        NAME,Phone,EMAIL
        Priya,9876543210,priya@example.com
        """
        let report = CustomerImportService.parse(csv: csv)
        XCTAssertEqual(report.parsed.count, 1)
        XCTAssertEqual(report.parsed[0].name, "Priya")
    }

    func testMissingNameColumnReturnsSkipped() {
        let csv = """
        phone,email
        9876543210,priya@example.com
        """
        let report = CustomerImportService.parse(csv: csv)
        XCTAssertEqual(report.parsed.count, 0)
        XCTAssertGreaterThan(report.skipped.count, 0)
        XCTAssertTrue(report.skipped[0].1.contains("name"))
    }

    func testRowMissingNameIsSkipped() {
        let csv = """
        name,phone
        Priya,9876543210
        ,8765432109
        Aman,7654321098
        """
        let report = CustomerImportService.parse(csv: csv)
        XCTAssertEqual(report.parsed.count, 2)
        XCTAssertEqual(report.skipped.count, 1)
        XCTAssertEqual(report.parsed.map(\.name), ["Priya", "Aman"])
    }

    func testQuotedCommaInsideField() {
        let csv = """
        name,phone,tags
        "Mehta, Priya",9876543210,"vip;bride"
        """
        let report = CustomerImportService.parse(csv: csv)
        XCTAssertEqual(report.parsed.count, 1)
        XCTAssertEqual(report.parsed[0].name, "Mehta, Priya")
        XCTAssertEqual(report.parsed[0].tags, ["vip", "bride"])
    }

    func testEscapedQuotesInsideQuotedField() {
        let csv = """
        name,phone
        "Priya ""P"" Mehta",9876543210
        """
        let report = CustomerImportService.parse(csv: csv)
        XCTAssertEqual(report.parsed.count, 1)
        XCTAssertEqual(report.parsed[0].name, "Priya \"P\" Mehta")
    }

    func testCRLFLineEndings() {
        let csv = "name,phone\r\nPriya,9876543210\r\nAman,8765432109\r\n"
        let report = CustomerImportService.parse(csv: csv)
        XCTAssertEqual(report.parsed.count, 2)
    }

    func testTagsSemicolonSplit() {
        let csv = """
        name,tags
        Priya,bride; vip ; festive
        """
        let report = CustomerImportService.parse(csv: csv)
        XCTAssertEqual(report.parsed[0].tags, ["bride", "vip", "festive"])
    }

    func testBooleanParsing() {
        let csv = """
        name,vip,whatsapp_consent
        Priya,yes,true
        Aman,N,0
        """
        let report = CustomerImportService.parse(csv: csv)
        XCTAssertEqual(report.parsed[0].vip, true)
        XCTAssertEqual(report.parsed[0].whatsappConsent, true)
        XCTAssertEqual(report.parsed[1].vip, false)
        XCTAssertEqual(report.parsed[1].whatsappConsent, false)
    }

    func testUnknownHeadersIgnored() {
        let csv = """
        name,phone,favourite_color,zodiac
        Priya,9876543210,blue,Aries
        """
        let report = CustomerImportService.parse(csv: csv)
        XCTAssertEqual(report.parsed.count, 1)
        XCTAssertEqual(report.parsed[0].name, "Priya")
        XCTAssertEqual(report.parsed[0].phone, "9876543210")
    }

    func testEmptyFileReturnsEmpty() {
        let report = CustomerImportService.parse(csv: "")
        XCTAssertEqual(report.parsed.count, 0)
    }

    func testHeaderOnlyFileReturnsEmpty() {
        let report = CustomerImportService.parse(csv: "name,phone")
        XCTAssertEqual(report.parsed.count, 0)
    }
}
