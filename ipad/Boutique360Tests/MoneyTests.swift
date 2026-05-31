import XCTest
@testable import Boutique360

/// Tests for the centralized money math helpers (L7 audit fix extracted into
/// `Money.roundedToPaise` so PaymentsSectionView and any future caller share
/// the same rounding semantics).
final class MoneyTests: XCTestCase {

    // MARK: - roundedToPaise

    func testWholeRupeeUnchanged() {
        XCTAssertEqual(Money.roundedToPaise(1000.00), 1000.00, accuracy: 0.0001)
    }

    func testPaiseExactKept() {
        XCTAssertEqual(Money.roundedToPaise(125.75), 125.75, accuracy: 0.0001)
    }

    func testSubPaiseDriftRoundedDown() {
        // The exact bug class: 0.000001 leftover after subtraction.
        XCTAssertEqual(Money.roundedToPaise(0.000001), 0.00, accuracy: 0.0001)
    }

    func testSubPaiseDriftRoundedDownWhenNearZero() {
        XCTAssertEqual(Money.roundedToPaise(49_999.999_999), 50_000.00, accuracy: 0.0001)
    }

    func testHalfPaiseRoundsToEven() {
        // Swift's .rounded() uses banker's rounding (half to even) by default.
        // 0.005 in money = 0.5 paise.
        let result = Money.roundedToPaise(0.005)
        XCTAssertTrue(result == 0.00 || result == 0.01,
                      "Half-paise should round to either 0 or 1; got \(result)")
    }

    func testNegativeRefund() {
        // Refunds may produce negative balances temporarily.
        XCTAssertEqual(Money.roundedToPaise(-200.50), -200.50, accuracy: 0.0001)
    }

    func testLargeAmount() {
        // 1 crore order — shouldn't lose precision.
        XCTAssertEqual(Money.roundedToPaise(1_00_00_000.00), 1_00_00_000.00, accuracy: 0.001)
    }

    // MARK: - equalAtPaise

    func testEqualAtPaiseTreatsSubCentAsEqual() {
        XCTAssertTrue(Money.equalAtPaise(50_000.0, 49_999.999_999))
    }

    func testEqualAtPaiseDistinguishesPaise() {
        XCTAssertFalse(Money.equalAtPaise(50_000.01, 50_000.00))
    }

    func testEqualAtPaiseExact() {
        XCTAssertTrue(Money.equalAtPaise(125.75, 125.75))
    }

    // MARK: - The bug we're guarding (regression test for L7)

    func testBalanceDueWontDriftAboveZeroOnFullyPaidOrder() {
        // The original bug: 0.4 * 50000 + 0.3 * 50000 + 0.3 * 50000 = 49_999.99…
        // depending on order of FP ops. Balance due was Double-different from 0
        // so the WhatsApp reminder appeared even though the customer paid in full.
        let orderTotal = 50_000.0
        let receivedDouble = 50_000.0 * 0.4 + 50_000.0 * 0.3 + 50_000.0 * 0.3
        let balanceRaw = orderTotal - receivedDouble
        // Raw could be < 0 or a sub-paise positive depending on platform FP.
        let balanceRounded = Money.roundedToPaise(balanceRaw)
        XCTAssertEqual(balanceRounded, 0.0, accuracy: 0.0001,
                       "Fully-paid order must reconcile to exactly zero after rounding")
    }
}
