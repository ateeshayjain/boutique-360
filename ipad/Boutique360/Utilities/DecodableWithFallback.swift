import Foundation

/// Upgrade Path §3 / Sync §A — tolerate raw values this build has never heard of.
///
/// **The failure it prevents.** Enums decode strictly by default, so a row
/// written by a newer app version (`status: "refunded"`) throws — and because
/// lists decode as an array, one unfamiliar value takes out *every* row. The
/// owner sees an empty Orders screen with no explanation. That is the worst
/// possible shape for this bug: total, silent, and triggered by someone else's
/// upgrade.
///
/// **What a "safe" fallback means here.** Not "closest guess" — *least
/// harmful*. The row must render, and it must not invite an action premised on
/// a state this build cannot see. `OrderStatus` therefore gets a real
/// `.unknown` case with no transitions rather than falling back to `.pending`,
/// where the owner could "confirm" an order that was actually refunded.
///
/// Every fallback is logged. A silent fallback is how you discover the schema
/// drifted six months late.
protocol DecodableWithFallback: RawRepresentable, Decodable where RawValue == String {
    /// The value to use when the raw string is unrecognised.
    static var decodingFallback: Self { get }
}

extension DecodableWithFallback {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let known = Self(rawValue: raw) {
            self = known
        } else {
            // `.public` is safe: these are schema enum values, never customer
            // data. Logging the type + value is what makes drift findable.
            Log.app.error("""
                Unknown \(String(describing: Self.self), privacy: .public) \
                value "\(raw, privacy: .public)" — falling back to \
                "\(Self.decodingFallback.rawValue, privacy: .public)". \
                A newer app version probably wrote this row.
                """)
            self = Self.decodingFallback
        }
    }
}
