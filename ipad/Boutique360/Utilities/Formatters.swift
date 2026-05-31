import Foundation

/// Single source of truth for currency / number / date formatting across the app.
///
/// Was previously duplicated in 5+ files — extracted per audit.
enum Formatters {
    /// Indian Rupee currency. Whole-rupee precision by default (no paise) because
    /// boutique transactions are essentially always whole-rupee.
    static let inr: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "INR"
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "en_IN")  // forces lakh-style grouping (1,31,250)
        return f
    }()

    /// INR with paise precision — for the rare orders that need it.
    static let inrPrecise: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "INR"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        f.locale = Locale(identifier: "en_IN")
        return f
    }()

    static func inr(_ value: Double, precise: Bool = false) -> String {
        let n = NSNumber(value: value)
        return (precise ? inrPrecise : inr).string(from: n) ?? "₹\(Int(value))"
    }

    // MARK: - Dates
    //
    // Reuse a single instance — `DateFormatter()` is expensive to allocate
    // (locale lookup on every init). These were previously allocated inside
    // loops in DashboardView.fetchUpcomingDates and ImportantDatesListView.load
    // — measurable cost on customer-heavy boutiques.

    /// "yyyy-MM-dd" for Postgres DATE columns (DOB, event_date, due_date).
    static let postgresDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")   // POSIX = not locale-dependent
        f.timeZone = TimeZone(identifier: "Asia/Kolkata")
        return f
    }()

    /// ISO8601 with fractional-second precision — for consent timestamps and
    /// audit logs where round-trip stability matters.
    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// ISO8601 without fractional seconds — Supabase ts columns + JSON inputs.
    static let iso8601Basic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

// MARK: - Money math

/// Centralized money rounding. Prevents the sub-paise drift that originally
/// surfaced a "balance due ₹0.000001" reminder for fully-paid orders (L7 audit fix).
/// Extracted so PaymentsSectionView and any future money-comparison code share
/// the same definition.
enum Money {
    /// Round to paise (2 decimal places, half-to-even via Swift's `rounded()`).
    /// 50.000001 → 50.00; 50.005 → 50.00 (banker's rounding); 50.006 → 50.01.
    static func roundedToPaise(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    /// `true` if `a` and `b` are equal when both rounded to paise. Use this for
    /// "is this order paid in full?" comparisons instead of `==` on Double.
    static func equalAtPaise(_ a: Double, _ b: Double) -> Bool {
        roundedToPaise(a) == roundedToPaise(b)
    }
}
