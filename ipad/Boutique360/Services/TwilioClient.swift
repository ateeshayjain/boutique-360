import Foundation

/// Minimal Twilio "send SMS" client.
///
/// Twilio uses HTTP Basic auth (SID + Auth Token), form-encoded body, and
/// returns JSON. Same justification as SendGridClient — one endpoint,
/// custom client beats a transitive dependency.
///
/// **India-specific note:** Inbound DLT registration is required to send
/// non-transactional SMS to Indian numbers. Twilio does NOT validate that
/// for you; the message will simply fail with a 21610-class error. The
/// caller's job is to honor `customer.consentWhatsapp` / `consent_email`
/// before calling — for SMS we re-use `consentWhatsapp` since the consent
/// is conceptually "messaging" (a `consent_sms` field is a future TODO if
/// we want fine-grained channel consent).
enum TwilioClient {
    enum Error: Swift.Error, LocalizedError {
        case notConfigured
        case invalidRecipient(String)
        case http(Int, String)
        case transport(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "SMS is not configured. Add TWILIO_SID/TWILIO_AUTH_TOKEN/TWILIO_FROM in Settings."
            case .invalidRecipient(let r):
                return "Invalid phone number: \(r)"
            case .http(let code, let body):
                return "Twilio HTTP \(code): \(body)"
            case .transport(let e):
                return "SMS transport failed: \(e.localizedDescription)"
            }
        }
    }

    /// Send a single SMS. Body is plain text; Twilio splits long messages
    /// into multiple SMS automatically (billed per segment). Keep under
    /// 160 ASCII chars to stay in 1 segment.
    static func send(to: String, body: String) async throws {
        guard Config.smsEnabled else { throw Error.notConfigured }
        let normalized = normalize(to)
        guard !normalized.isEmpty else { throw Error.invalidRecipient(to) }

        let urlStr = "https://api.twilio.com/2010-04-01/Accounts/\(Config.twilioSid)/Messages.json"
        var req = URLRequest(url: URL(string: urlStr)!)
        req.httpMethod = "POST"
        let basic = "\(Config.twilioSid):\(Config.twilioAuthToken)"
            .data(using: .utf8)!
            .base64EncodedString()
        req.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [(String, String)] = [
            ("To", normalized),
            ("From", Config.twilioFrom),
            ("Body", body)
        ]
        req.httpBody = formEncode(params).data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw Error.http(0, "no http response")
            }
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

    /// Coerce loose Indian phone formats into E.164 (`+91XXXXXXXXXX`).
    /// We accept: "9876543210", "919876543210", "+919876543210", "(98)76 54 32 10".
    /// Anything else returns "" (caller treats as invalid).
    /// Exposed `internal` so tests can verify the normalization rules.
    static func normalize(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        guard !digits.isEmpty else { return "" }
        if raw.hasPrefix("+") {
            // Already E.164 — keep the +, strip everything non-digit after.
            return "+" + digits
        }
        switch digits.count {
        case 10:                 return "+91" + digits           // bare Indian mobile
        case 11 where digits.hasPrefix("0"):
            return "+91" + String(digits.dropFirst())            // 0XXXXXXXXXX
        case 12 where digits.hasPrefix("91"):
            return "+" + digits                                  // 91XXXXXXXXXX
        case 13 where digits.hasPrefix("091"):
            return "+" + String(digits.dropFirst())              // 091XXXXXXXXXX
        default:
            return ""
        }
    }

    private static func formEncode(_ pairs: [(String, String)]) -> String {
        pairs.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
    }
}
