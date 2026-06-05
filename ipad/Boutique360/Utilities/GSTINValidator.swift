import Foundation

/// M10 partial: structural GSTIN validator.
///
/// Format (per GSTN spec): 15 chars
///   - chars 1-2: state code (digits)
///   - chars 3-12: PAN (5 letters + 4 digits + 1 letter)
///   - char  13: entity number (digit or letter)
///   - char  14: literal 'Z'
///   - char  15: check digit / character
///
/// This validates the *structure* — sufficient to catch human typos at form
/// submission time. The full mod-36 checksum is not implemented here; can be
/// added later when audits become a concern.
enum GSTINValidator {
    static let pattern = "^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$"

    /// Returns nil if valid, otherwise a short human-readable problem.
    static func problem(in raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespaces).uppercased()
        if s.isEmpty { return nil } // empty is allowed — GSTIN is optional
        guard s.count == 15 else {
            return "GSTIN should be 15 characters (got \(s.count))"
        }
        if s.range(of: pattern, options: .regularExpression) == nil {
            return "GSTIN format looks wrong (e.g. 07AABCS1234A1Z5)"
        }
        return nil
    }

    static func isValid(_ raw: String) -> Bool {
        problem(in: raw) == nil
    }
}
