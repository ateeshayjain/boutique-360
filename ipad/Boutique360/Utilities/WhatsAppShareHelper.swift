import Foundation
import UIKit

/// Single source of truth for "open WhatsApp with a pre-filled message to <phone>".
///
/// Used by: render share, VTO share, order-status update, payment reminder,
/// important-date greeting, customer profile quick action.
///
/// Uses the universal `wa.me` link rather than the `whatsapp://` scheme so we
/// don't have to declare `LSApplicationQueriesSchemes` in Info.plist. iOS opens
/// it in the WhatsApp app if installed, otherwise the system browser falls back
/// to web.whatsapp.com.
enum WhatsAppShareHelper {
    /// Builds the URL (no side-effects). Returns nil if the phone is unusable.
    static func url(phone: String?, message: String) -> URL? {
        guard let normalized = normalizeIndianPhone(phone), !normalized.isEmpty else { return nil }
        var components = URLComponents(string: "https://wa.me/\(normalized)")
        components?.queryItems = [URLQueryItem(name: "text", value: message)]
        return components?.url
    }

    /// Open WhatsApp pre-filled. Returns true if the OS accepted the open request.
    @discardableResult
    static func open(phone: String?, message: String) -> Bool {
        guard let url = url(phone: phone, message: message) else { return false }
        guard UIApplication.shared.canOpenURL(url) else {
            // Fall back to a generic share if we somehow can't open https.
            return false
        }
        UIApplication.shared.open(url)
        return true
    }

    /// Strips everything but digits and prepends India country code (91) if missing.
    /// Returns nil for empty/clearly-invalid numbers.
    static func normalizeIndianPhone(_ raw: String?) -> String? {
        guard let raw = raw else { return nil }
        let digits = raw.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.map(Character.init)
        let s = String(digits)
        guard s.count >= 10 else { return nil }
        if s.hasPrefix("91") && s.count == 12 { return s }
        if s.count == 10 { return "91" + s }
        return s   // already country-coded
    }
}
