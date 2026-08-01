import Foundation

/// Security §8 (AI/LLM privacy) + Testing §2 (validation/sanitization).
///
/// Everything here is pure and tested. The checklist's sharpest line about
/// this area is "built ≠ called; verify the call site" — so the redactor is
/// applied inside `GeminiService`'s prompt builders, not left for each caller
/// to remember.
///
/// Scope, stated honestly: this reduces the PII that leaves the device and
/// blunts the obvious prompt-injection shapes. It is **not** a guarantee.
/// A determined injection can survive pattern-matching, and free-text notes
/// can carry identifying detail no regex will catch ("Sharma ji's daughter's
/// sangeet"). The structural mitigations matter more: the app sends
/// structured fields rather than whole records, and never sends the
/// customer's name, phone, email, or address to the model at all.
enum AISafety {
    static let maxPromptFieldLength = 2_000
    static let maxModelOutputLength = 8_000

    // MARK: - PII redaction

    /// Order matters: longer/more specific patterns first, so a GSTIN isn't
    /// half-eaten by the PAN rule it contains.
    private static let piiPatterns: [String] = [
        // Email
        #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
        // GSTIN: 15 chars, 2-digit state + PAN + 3
        #"\b\d{2}[A-Z]{5}\d{4}[A-Z]\d[A-Z][A-Z0-9]\b"#,
        // PAN: 5 letters, 4 digits, 1 letter
        #"\b[A-Z]{5}\d{4}[A-Z]\b"#,
        // Aadhaar: 12 digits, optionally spaced 4-4-4
        #"\b\d{4}\s?\d{4}\s?\d{4}\b"#,
        // Indian phone: optional +91 / leading-0 prefix, then 10 digits with
        // an optional separator. The prefix alternatives each carry their own
        // anchor — a `\b` *after* an optional `0` never matches, because `0`
        // and the following digit are both word characters.
        #"(?:\+91[\s-]?|\b0|\b)[6-9]\d{4}[\s-]?\d{5}\b"#,
    ]

    /// Replaces contact identifiers with `[redacted]`. Deliberately tuned to
    /// leave tailoring text intact — 2- and 3-digit measurements must survive,
    /// which is why the phone rule requires a 10-digit run starting 6–9.
    static func redactPII(_ text: String) -> String {
        var out = text
        for pattern in piiPatterns {
            guard let rx = try? NSRegularExpression(pattern: pattern) else { continue }
            out = rx.stringByReplacingMatches(
                in: out, range: NSRange(out.startIndex..., in: out),
                withTemplate: "[redacted]")
        }
        return out
    }

    // MARK: - Prompt input

    /// Phrases whose only purpose in a *design note* is to talk to the model.
    private static let injectionMarkers = [
        "ignore previous instructions", "ignore all previous",
        "disregard previous", "disregard the above",
        "system prompt", "you are now", "new instructions:",
        "forget everything",
    ]

    /// Applied to every free-text field interpolated into a prompt:
    /// redact → strip injection markers → neutralise the prompt's own
    /// delimiters → cap length.
    static func sanitizePromptInput(_ text: String) -> String {
        var out = redactPII(text)

        for marker in injectionMarkers {
            var searchRange = out.startIndex..<out.endIndex
            while let found = out.range(of: marker, options: .caseInsensitive, range: searchRange) {
                out.replaceSubrange(found, with: "[removed]")
                guard let next = out.range(of: "[removed]") else { break }
                searchRange = next.upperBound..<out.endIndex
            }
        }

        // The prompt fences user data inside ----- DESIGN DATA ----- markers.
        // A note containing a closing fence could otherwise escape the data
        // section and be read as instructions.
        out = out.replacingOccurrences(of: "-----", with: "—")

        if out.count > maxPromptFieldLength {
            // Reserve one character for the ellipsis so the result honours the
            // cap it advertises.
            out = String(out.prefix(maxPromptFieldLength - 1)) + "…"
        }
        return out
    }

    // MARK: - Model output

    /// Strips control characters (keeping newlines — the brief is multiline)
    /// and caps length before the text reaches a PDF, a database column, and
    /// ultimately the karigar's HTML page.
    static func sanitizeModelOutput(_ text: String) -> String {
        let filtered = String(String.UnicodeScalarView(
            text.unicodeScalars.filter { scalar in
                scalar == "\n" || scalar == "\t"
                    || scalar.properties.generalCategory != .control
            }))
        var out = filtered.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.count > maxModelOutputLength {
            out = String(out.prefix(maxModelOutputLength))
        }
        return out
    }

    // MARK: - Errors

    /// Security §12 / Testing §6: error responses must not leak internals.
    /// Upstream Gemini bodies can carry key fragments, quota identifiers and
    /// internal status strings, and this app puts error text straight in front
    /// of the owner — so the raw body is logged, never displayed.
    static func userFacingAIError(status: Int, body: String) -> String {
        Log.ai.error("Gemini \(status, privacy: .public) — \(body.prefix(500), privacy: .private)")
        switch status {
        case 429:        return "The AI service is busy right now. Wait a moment and try again."
        case 401, 403:   return "The AI service rejected our credentials. Check GEMINI_API_KEY in Secrets.xcconfig."
        case 500...599:  return "The AI service is having trouble. Try again shortly."
        default:         return "The AI request failed. Try again — if it keeps failing, check the AI settings."
        }
    }
}
