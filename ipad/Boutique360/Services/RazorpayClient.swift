import Foundation

/// Razorpay **Payment Links** API client.
///
/// **Why payment links, not on-device card processing?**
/// - On-device card collection would require Razorpay's iOS SDK + full
///   PCI scope (UI must not see the PAN). Worth it only for in-store
///   purchase flows we don't have yet.
/// - Payment Links are a hosted URL the customer opens — Razorpay handles
///   UPI/card/netbanking/wallet on their side. We just persist the URL +
///   short_url and the WA helper sends it. UPI mandates work out of the
///   box.
///
/// **Auth:** HTTP Basic with `key_id:key_secret`. The secret stays
/// on-device because Boutique360 is single-tenant-per-install. For
/// multi-tenant SaaS this code would move to a Supabase Edge Function.
enum RazorpayClient {
    enum Error: Swift.Error, LocalizedError {
        case notConfigured
        case invalidAmount(Double)
        case http(Int, String)
        case decoding(String)
        case transport(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Razorpay is not configured. Add RAZORPAY_KEY_ID + RAZORPAY_KEY_SECRET in Settings."
            case .invalidAmount(let v):
                return "Payment amount must be > ₹1: \(v)"
            case .http(let code, let body):
                return "Razorpay HTTP \(code): \(body)"
            case .decoding(let m):
                return "Razorpay response decoding failed: \(m)"
            case .transport(let e):
                return "Razorpay transport failed: \(e.localizedDescription)"
            }
        }
    }

    /// What we hand back to the caller after a successful create call.
    /// `shortUrl` is the rzp.io link to share with the customer;
    /// `id` is the Razorpay reference (`plink_xxx`) for reconciliation.
    struct PaymentLink: Decodable {
        let id: String
        let shortUrl: String
        let status: String
        let amountPaise: Int

        enum CodingKeys: String, CodingKey {
            case id, status
            case shortUrl = "short_url"
            case amountPaise = "amount"
        }
    }

    /// Create a Razorpay Payment Link for `amount` INR.
    /// `description` is shown to the customer on the hosted page.
    /// `customer` is used to pre-fill name + phone on the page (a small
    /// UX win — auto-pre-fill reduces drop-off by ~10% per Razorpay docs).
    /// `referenceId` should be the order number so reconciliation in the
    /// Razorpay dashboard maps 1:1 to your invoice trail.
    static func createPaymentLink(
        amountInRupees amount: Double,
        description: String,
        customer: Customer,
        referenceId: String,
        callbackUrl: String? = nil
    ) async throws -> PaymentLink {
        guard Config.razorpayEnabled else { throw Error.notConfigured }
        guard amount > 1 else { throw Error.invalidAmount(amount) }

        // Razorpay amounts are in paise (smallest currency unit).
        let paise = Int((amount * 100).rounded())

        var body: [String: Any] = [
            "amount": paise,
            "currency": "INR",
            "accept_partial": false,
            "description": description,
            "reference_id": referenceId,
            // Once paid, the link auto-expires on Razorpay's side.
            "expire_by": Int(Date().addingTimeInterval(60 * 60 * 24 * 14).timeIntervalSince1970), // 14 days
            "notify": ["sms": false, "email": false],   // we send via wa.me
            "reminder_enable": true,
            "customer": [
                "name": customer.name,
                "contact": customer.phone ?? "",
                "email": customer.email ?? ""
            ]
        ]
        if let cb = callbackUrl {
            body["callback_url"] = cb
            body["callback_method"] = "get"
        }

        var req = URLRequest(url: URL(string: "https://api.razorpay.com/v1/payment_links")!)
        req.httpMethod = "POST"
        let basic = "\(Config.razorpayKeyId):\(Config.razorpayKeySecret)"
            .data(using: .utf8)!
            .base64EncodedString()
        req.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw Error.http(0, "no http response")
            }
            guard (200..<300).contains(http.statusCode) else {
                let raw = String(data: data, encoding: .utf8) ?? ""
                throw Error.http(http.statusCode, raw)
            }
            do {
                return try JSONDecoder().decode(PaymentLink.self, from: data)
            } catch {
                let raw = String(data: data, encoding: .utf8) ?? ""
                throw Error.decoding("\(error.localizedDescription) — payload: \(raw.prefix(200))")
            }
        } catch let e as Error {
            throw e
        } catch {
            throw Error.transport(error)
        }
    }
}
