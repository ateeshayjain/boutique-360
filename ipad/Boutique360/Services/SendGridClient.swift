import Foundation

/// Minimal SendGrid v3 mail-send client.
///
/// **Why a tiny custom client instead of a Swift package?**
/// - One endpoint (`POST /v3/mail/send`), one auth header — vendored deps
///   for ~30 LOC don't pay rent.
/// - Keeps the dependency surface honest: we already justify Supabase +
///   Gemini network calls. SendGrid is just URLSession.
///
/// **What this does NOT do:**
/// - No retry, no queue. A failed send returns the error to the caller —
///   the View decides whether to surface "try again" or fail silently.
/// - No template rendering. Caller passes finished HTML + plain text.
///   Boutique templates live in `NotificationTemplates`.
enum SendGridClient {
    enum Error: Swift.Error, LocalizedError {
        case notConfigured
        case invalidRecipient(String)
        case http(Int, String)
        case transport(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Email is not configured. Add SENDGRID_API_KEY + SENDGRID_FROM in Settings."
            case .invalidRecipient(let r):
                return "Invalid email address: \(r)"
            case .http(let code, let body):
                return "SendGrid HTTP \(code): \(body)"
            case .transport(let e):
                return "Email transport failed: \(e.localizedDescription)"
            }
        }
    }

    /// Send a single email. `htmlBody` is required; `plainBody` is generated
    /// from it (tags stripped) if omitted — every modern client falls back
    /// to plain text when HTML fails to render.
    static func send(
        to: String,
        toName: String?,
        subject: String,
        htmlBody: String,
        plainBody: String? = nil
    ) async throws {
        guard Config.emailEnabled else { throw Error.notConfigured }
        let trimmed = to.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("@"), trimmed.count >= 5 else {
            throw Error.invalidRecipient(to)
        }

        let plain = plainBody ?? stripTags(htmlBody)
        let body: [String: Any] = [
            "personalizations": [[
                "to": [["email": trimmed, "name": toName ?? trimmed]]
            ]],
            "from": parseFrom(Config.sendgridFrom),
            "subject": subject,
            "content": [
                ["type": "text/plain", "value": plain],
                ["type": "text/html",  "value": htmlBody]
            ],
            // Tracking: disabled by default to honor DPDP minimization.
            "tracking_settings": [
                "click_tracking": ["enable": false],
                "open_tracking":  ["enable": false]
            ]
        ]

        var req = URLRequest(url: URL(string: "https://api.sendgrid.com/v3/mail/send")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(Config.sendgridApiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw Error.http(0, "no http response")
            }
            // SendGrid returns 202 Accepted on success.
            guard (200..<300).contains(http.statusCode) else {
                let raw = String(data: data, encoding: .utf8) ?? ""
                throw Error.http(http.statusCode, raw)
            }
        } catch let e as Error {
            throw e
        } catch {
            throw Error.transport(error)
        }
    }

    /// SendGrid's `from` field accepts `{email, name}`. We parse two formats:
    /// 1) `Boutique Name <hello@boutique.in>` — name + email
    /// 2) `hello@boutique.in` — bare email
    private static func parseFrom(_ raw: String) -> [String: String] {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let lt = trimmed.firstIndex(of: "<"), let gt = trimmed.firstIndex(of: ">") {
            let name = trimmed[..<lt].trimmingCharacters(in: .whitespaces)
            let email = String(trimmed[trimmed.index(after: lt)..<gt])
            return ["email": email, "name": name]
        }
        return ["email": trimmed, "name": trimmed]
    }

    /// Strip HTML tags for the plain-text fallback. We're not aiming for
    /// pretty plaintext — just legible enough for screen readers + spam
    /// filters that downgrade emails without text/plain.
    private static func stripTags(_ html: String) -> String {
        let pattern = "<[^>]+>"
        let stripped = html.replacingOccurrences(
            of: pattern, with: " ", options: .regularExpression
        )
        return stripped
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
