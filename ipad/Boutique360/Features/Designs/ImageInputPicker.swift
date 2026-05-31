import SwiftUI
import PhotosUI
import UIKit

enum URLInputError: Equatable { case empty, notHTTP, likelyBlockedHost, malformed }

/// Pure, testable URL validation. No global state, no network — just structural checks.
enum ImageURLValidator {
    private static let blockedHosts = ["instagram.com", "pinterest.com", "pin.it"]
    static func validate(_ raw: String) -> Result<URL, URLInputError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return .failure(.malformed) }
        guard scheme == "http" || scheme == "https" else { return .failure(.notHTTP) }
        let host = (url.host ?? "").lowercased()
        if blockedHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return .failure(.likelyBlockedHost)
        }
        return .success(url)
    }
}
