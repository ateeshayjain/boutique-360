import Foundation

/// Pure aggregator over a customer's `Order` list.
///
/// Why pure: keeping the math out of the View makes it trivial to unit-test
/// (no SwiftUI, no Supabase) and lets us reuse the same numbers from the
/// dashboard later. The View just renders what this returns.
///
/// **Definition decisions** (worth being explicit about):
/// - **Spend = total of orders NOT in `cancelled` or `returned`.** This is
///   "billed and kept" — the most useful number for a boutique deciding
///   whether to comp a small gift on a future order. Counting cancelled
///   orders would inflate VIP status falsely; ignoring `returned` would
///   miss legitimate returns reducing real revenue.
/// - **Avg order value uses the same filtered set.** Same reasoning.
/// - **Last-12-months buckets** are keyed by the order's `placedAt ??
///   createdAt`, anchored to "now" passed in (so tests are deterministic).
enum CustomerSpend {
    struct Summary {
        let lifetimeSpend: Double
        let orderCount: Int
        let avgOrderValue: Double
        let firstOrderAt: Date?
        let lastOrderAt: Date?
        /// Ordered oldest → newest. Always exactly 12 entries when
        /// `monthlyTotals` is requested via `summarize`.
        let monthlyTotals: [MonthlyTotal]
    }

    struct MonthlyTotal: Identifiable, Hashable {
        let monthStart: Date
        let total: Double
        var id: Date { monthStart }
        var label: String {
            monthStart.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
        }
    }

    /// Cancelled + returned orders are excluded from spend math but still
    /// reflected in `orderCount`'s denominator for avg only when they sit
    /// in the filtered set — i.e. they're excluded everywhere.
    static func summarize(_ orders: [Order], now: Date = Date(), calendar: Calendar = .current) -> Summary {
        let billed = orders.filter { $0.status != .cancelled && $0.status != .returned }
        let lifetime = billed.reduce(0.0) { $0 + $1.total }
        let count = billed.count
        let avg = count > 0 ? lifetime / Double(count) : 0
        let dates = billed.map { $0.placedAt ?? $0.createdAt }.sorted()
        let monthly = bucketLast12Months(billed: billed, now: now, calendar: calendar)
        return Summary(
            lifetimeSpend: lifetime,
            orderCount: count,
            avgOrderValue: avg,
            firstOrderAt: dates.first,
            lastOrderAt: dates.last,
            monthlyTotals: monthly
        )
    }

    /// Build 12 month buckets ending at the month containing `now`.
    /// Months with no orders are emitted with `total = 0` so the chart
    /// draws a continuous timeline (avoids "missing month" gaps).
    private static func bucketLast12Months(billed: [Order], now: Date, calendar: Calendar) -> [MonthlyTotal] {
        guard let thisMonthStart = calendar.dateInterval(of: .month, for: now)?.start else { return [] }
        // 12 anchors: 11 months back through current month.
        let anchors: [Date] = (0..<12).reversed().compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: thisMonthStart)
        }
        var totals = [Date: Double](uniqueKeysWithValues: anchors.map { ($0, 0.0) })
        for o in billed {
            let when = o.placedAt ?? o.createdAt
            guard let bucket = calendar.dateInterval(of: .month, for: when)?.start,
                  totals[bucket] != nil else { continue }
            totals[bucket, default: 0] += o.total
        }
        return anchors.map { MonthlyTotal(monthStart: $0, total: totals[$0] ?? 0) }
    }
}
