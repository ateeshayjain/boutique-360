import Foundation

/// Reads build-time environment from Info.plist (populated via Env.xcconfig).
/// Fatal-errors at startup if a required value is missing — better than silently misbehaving.
enum Config {
    static let supabaseURL: URL = {
        let raw = readRequiredString("SUPABASE_URL")
        guard let url = URL(string: raw) else {
            fatalError("Config.SUPABASE_URL is not a valid URL: \(raw)")
        }
        return url
    }()

    static let supabaseAnonKey: String = readRequiredString("SUPABASE_ANON_KEY")

    /// Optional. AI features (render + try-on) disabled when empty.
    /// Add to Env.xcconfig: `GEMINI_API_KEY = your-key-here`
    static let geminiApiKey: String = readOptionalString("GEMINI_API_KEY")
    static var aiEnabled: Bool { !geminiApiKey.isEmpty }

    // MARK: - Wave 3: Email (SendGrid)
    /// Optional. Email notifications disabled when empty.
    /// Add to Secrets.xcconfig: `SENDGRID_API_KEY = SG.xxxxxxx`
    static let sendgridApiKey: String = readOptionalString("SENDGRID_API_KEY")
    /// "From" identity used on outbound mail. Must be a SendGrid-verified
    /// sender. Format: `Boutique Name <hello@boutique.in>` OR plain email.
    static let sendgridFrom: String = readOptionalString("SENDGRID_FROM")
    static var emailEnabled: Bool { !sendgridApiKey.isEmpty && !sendgridFrom.isEmpty }

    // MARK: - Wave 3: SMS (Twilio)
    /// Optional. SMS notifications disabled when any of these is empty.
    /// Add to Secrets.xcconfig: `TWILIO_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM`
    static let twilioSid: String = readOptionalString("TWILIO_SID")
    static let twilioAuthToken: String = readOptionalString("TWILIO_AUTH_TOKEN")
    /// Twilio sender number in E.164 (e.g. "+12025551234") or an alphanumeric
    /// sender ID where supported (India: register with DLT first).
    static let twilioFrom: String = readOptionalString("TWILIO_FROM")
    static var smsEnabled: Bool {
        !twilioSid.isEmpty && !twilioAuthToken.isEmpty && !twilioFrom.isEmpty
    }

    // MARK: - Wave 4: Razorpay payment links
    /// Optional. Razorpay payment-link generation disabled when empty.
    /// Add to Secrets.xcconfig: `RAZORPAY_KEY_ID = rzp_test_xxx`, `RAZORPAY_KEY_SECRET = xxx`
    /// Note: secret stays on-device only because Boutique360 is single-tenant
    /// per install. For multi-tenant SaaS this would move to an Edge Function.
    static let razorpayKeyId: String = readOptionalString("RAZORPAY_KEY_ID")
    static let razorpayKeySecret: String = readOptionalString("RAZORPAY_KEY_SECRET")
    static var razorpayEnabled: Bool {
        !razorpayKeyId.isEmpty && !razorpayKeySecret.isEmpty
    }

    private static func readOptionalString(_ key: String) -> String {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
        return value.hasPrefix("$(") ? "" : value
    }

    private static func readRequiredString(_ key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.hasPrefix("$(")  // catch unsubstituted xcconfig vars
        else {
            fatalError("Missing required Info.plist key: \(key). Did Env.xcconfig get loaded?")
        }
        return value
    }
}
