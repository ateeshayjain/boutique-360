import XCTest
@testable import Boutique360

/// Pure-logic tests for the centralized Formatters utility.
/// Critical: en_IN locale produces lakh-style grouping (1,31,250) which the
/// device locale would NOT produce by default. Several earlier bugs were
/// formatter-misconfiguration; these tests pin the behavior.
final class FormattersTests: XCTestCase {

    // MARK: - INR currency

    func testInrUsesIndianLakhGrouping() {
        XCTAssertEqual(Formatters.inr(131_250),  "₹1,31,250")
        XCTAssertEqual(Formatters.inr(1_000_000), "₹10,00,000")
        XCTAssertEqual(Formatters.inr(50),       "₹50")
    }

    func testInrZeroAndNegative() {
        XCTAssertEqual(Formatters.inr(0), "₹0")
        // Negatives shouldn't crash; formatter falls back if locale rejects.
        XCTAssertFalse(Formatters.inr(-100).isEmpty)
    }

    func testInrRoundsToWholeRupeesByDefault() {
        XCTAssertEqual(Formatters.inr(125.75), "₹126")  // banker's rounding via NumberFormatter
    }

    func testInrPreciseKeepsPaise() {
        XCTAssertEqual(Formatters.inr(125.75, precise: true), "₹125.75")
        XCTAssertEqual(Formatters.inr(1_25_000.50, precise: true), "₹1,25,000.50")
    }

    // MARK: - Postgres date

    func testPostgresDateRoundTripIST() {
        // Build a moment that's 12:00 IST → not at risk of timezone drift.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let comps = DateComponents(year: 2026, month: 5, day: 26, hour: 12, minute: 0)
        let date = cal.date(from: comps)!

        let s = Formatters.postgresDate.string(from: date)
        XCTAssertEqual(s, "2026-05-26")

        let parsed = Formatters.postgresDate.date(from: s)!
        // Round-trip equality at IST midnight.
        let parsedComps = cal.dateComponents([.year, .month, .day], from: parsed)
        XCTAssertEqual(parsedComps.year, 2026)
        XCTAssertEqual(parsedComps.month, 5)
        XCTAssertEqual(parsedComps.day, 26)
    }

    func testPostgresDateAtMidnightIstStaysOnSameDay() {
        // The exact bug class we're guarding: DOB 2000-01-01 stored at midnight
        // IST shouldn't drift to 1999-12-31.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let midnight = cal.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: 0, minute: 0))!
        XCTAssertEqual(Formatters.postgresDate.string(from: midnight), "2000-01-01")
    }

    // MARK: - ISO 8601

    func testIso8601BasicRoundTrip() {
        let s = "2026-05-26T08:30:00Z"
        let date = Formatters.iso8601Basic.date(from: s)!
        XCTAssertEqual(Formatters.iso8601Basic.string(from: date), s)
    }

    func testIso8601WithFractionalSecondsForDpdpConsent() {
        // The DPDP consent timestamp needs sub-second precision; that's why we
        // have a separate iso8601 formatter with fractional seconds.
        let consentAt = Date()
        let s = Formatters.iso8601.string(from: consentAt)
        XCTAssertTrue(s.contains("."), "Expected fractional seconds in ISO 8601 consent timestamp")
        let parsed = Formatters.iso8601.date(from: s)!
        // Within 1ms of the original — fractional second precision retained.
        XCTAssertEqual(parsed.timeIntervalSince(consentAt), 0, accuracy: 0.001)
    }
}
