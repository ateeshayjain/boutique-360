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
/// Validates structure **and** the mod-36 check character.
///
/// The checksum was added 2026-08-01 after the structure-only version let a
/// placeholder (`07AAAAA0000A1Z5`, seeded by migration 0023) pass as real, so
/// the app enabled invoicing and generated GST invoices carrying a fabricated
/// tax ID. Structure alone cannot catch that; the check character can, and
/// does — a GSTIN with a wrong last character is arithmetically detectable
/// without contacting the GSTN.
///
/// What this still does NOT prove: that a checksum-valid GSTIN is *registered*,
/// or that it belongs to this boutique. Only the GSTN portal can confirm that.
enum GSTINValidator {
    static let pattern = "^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$"

    /// GSTN's alphabet: '0'–'9' map to 0–9, 'A'–'Z' to 10–35.
    private static let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    /// Returns nil if valid, otherwise a short human-readable problem.
    /// Structure is checked before the checksum, so a mistyped length reports
    /// the length rather than a confusing check-character complaint.
    static func problem(in raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespaces).uppercased()
        if s.isEmpty { return nil } // empty is allowed — GSTIN is optional
        guard s.count == 15 else {
            return "GSTIN should be 15 characters (got \(s.count))"
        }
        if s.range(of: pattern, options: .regularExpression) == nil {
            // The old example here (07AABCS1234A1Z5) was itself checksum-invalid
            // — the app was telling people to copy a malformed GSTIN.
            return "GSTIN format looks wrong (e.g. 07ABCDE1234F1Z2)"
        }
        guard let expected = checkCharacter(for: String(s.prefix(14))),
              expected == s.last else {
            return "GSTIN check character doesn't match — re-check the last character"
        }
        return nil
    }

    /// Mod-36 check character over the first 14 characters.
    /// Each character's value is multiplied by an alternating weight (1,2,1,2…),
    /// the product's base-36 digits are summed, and the check character is
    /// whatever brings the running total up to a multiple of 36.
    static func checkCharacter(for first14: String) -> Character? {
        guard first14.count == 14 else { return nil }
        var total = 0
        for (i, ch) in first14.enumerated() {
            guard let value = charset.firstIndex(of: ch) else { return nil }
            let product = value * (i.isMultiple(of: 2) ? 1 : 2)
            total += (product / 36) + (product % 36)
        }
        return charset[(36 - (total % 36)) % 36]
    }

    static func isValid(_ raw: String) -> Bool {
        problem(in: raw) == nil
    }
}
