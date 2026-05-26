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
}
