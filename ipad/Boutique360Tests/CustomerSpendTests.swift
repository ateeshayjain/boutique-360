import XCTest
@testable import Boutique360

/// Pure-aggregator tests for `CustomerSpend.summarize`.
///
/// We exercise the cases that matter for the boutique's actual mental
/// model — VIP-worthy customers (high lifetime, many orders), customers
/// with cancelled/returned mixed in (those must be excluded), and the
/// chart's "month with zero orders" continuity.
final class CustomerSpendTests: XCTestCase {

    // Helper — build a minimal Order. Many fields are irrelevant to spend math.
    private func makeOrder(
        total: Double,
        status: OrderStatus = .delivered,
        placedAt: Date,
        id: UUID = UUID()
    ) -> Order {
        // Decode from JSON because `Order` has no public init.
        // This is the cheapest way to construct one in tests without
        // touching the real schema.
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let placedStr = iso.string(from: placedAt)
        let dict: [String: Any] = [
            "id": id.uuidString,
            "boutique_id": UUID().uuidString,
            "order_number": "BQ-TEST",
            "customer_id": UUID().uuidString,
            "status": status.rawValue,
            "subtotal": total,
            "gst_amount": 0,
            "shipping": 0,
            "total": total,
            "currency": "INR",
            "placed_at": placedStr,
            "created_at": placedStr,
            "updated_at": placedStr
        ]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(Order.self, from: data)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    func testEmptyOrdersReturnsZeros() {
        let s = CustomerSpend.summarize([])
        XCTAssertEqual(s.lifetimeSpend, 0)
        XCTAssertEqual(s.orderCount, 0)
        XCTAssertEqual(s.avgOrderValue, 0)
        XCTAssertNil(s.firstOrderAt)
        XCTAssertNil(s.lastOrderAt)
    }

    func testCancelledAndReturnedExcludedFromSpend() {
        // 3 delivered + 1 cancelled + 1 returned. Only the delivered count.
        let orders = [
            makeOrder(total: 10_000, status: .delivered, placedAt: date(2026, 5, 1)),
            makeOrder(total: 5_000,  status: .delivered, placedAt: date(2026, 5, 15)),
            makeOrder(total: 2_500,  status: .delivered, placedAt: date(2026, 6, 1)),
            makeOrder(total: 99_999, status: .cancelled, placedAt: date(2026, 6, 2)),
            makeOrder(total: 88_888, status: .returned,  placedAt: date(2026, 6, 3))
        ]
        let s = CustomerSpend.summarize(orders, now: date(2026, 6, 8))
        XCTAssertEqual(s.lifetimeSpend, 17_500, accuracy: 0.01)
        XCTAssertEqual(s.orderCount, 3)
        XCTAssertEqual(s.avgOrderValue, 17_500.0 / 3.0, accuracy: 0.01)
    }

    func testTwelveMonthBucketsAreContinuousIncludingZeros() {
        // One order 11 months ago, one this month — gap months should all
        // appear with total: 0 so the chart doesn't have visual holes.
        let orders = [
            makeOrder(total: 1_000, status: .delivered, placedAt: date(2025, 7, 10)),
            makeOrder(total: 4_000, status: .delivered, placedAt: date(2026, 6, 5))
        ]
        let s = CustomerSpend.summarize(orders, now: date(2026, 6, 8))
        XCTAssertEqual(s.monthlyTotals.count, 12)
        XCTAssertGreaterThan(s.monthlyTotals.first!.total, 0)
        XCTAssertGreaterThan(s.monthlyTotals.last!.total, 0)
        // Middle bucket (e.g. Dec 2025) has no orders → zero, not absent.
        let dec = s.monthlyTotals.first(where: {
            Calendar(identifier: .gregorian).component(.month, from: $0.monthStart) == 12
        })
        XCTAssertNotNil(dec)
        XCTAssertEqual(dec!.total, 0)
    }

    func testOrderOlderThan12MonthsIsExcludedFromBuckets() {
        // 14 months back — outside the window. Counts toward lifetime spend
        // but doesn't appear in the chart.
        let orders = [
            makeOrder(total: 50_000, status: .delivered, placedAt: date(2025, 4, 1)),
            makeOrder(total: 1_000,  status: .delivered, placedAt: date(2026, 6, 1))
        ]
        let s = CustomerSpend.summarize(orders, now: date(2026, 6, 8))
        XCTAssertEqual(s.lifetimeSpend, 51_000, accuracy: 0.01)
        let chartedTotal = s.monthlyTotals.reduce(0.0) { $0 + $1.total }
        XCTAssertEqual(chartedTotal, 1_000, accuracy: 0.01,
                       "Order older than 12 months should be excluded from chart buckets")
    }
}
