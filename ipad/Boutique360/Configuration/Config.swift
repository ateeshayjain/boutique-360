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
