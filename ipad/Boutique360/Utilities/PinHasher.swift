import Foundation
import CryptoKit
import Security   // SecRandomCopyBytes lives here — NOT re-exported by
                  // Foundation or CryptoKit. Same import KeychainStore uses.

/// R4b — the PIN is never stored in plaintext (Security §2, §6).
/// Stored form: `"<base64 salt>:<base64 SHA256(salt ‖ pin)>"`.
enum PinHasher {
    static func newSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    static func digest(pin: String, salt: Data) -> Data {
        var input = salt
        input.append(Data(pin.utf8))
        return Data(SHA256.hash(data: input))
    }

    static func makeStored(pin: String) -> String {
        let salt = newSalt()
        return "\(salt.base64EncodedString()):\(digest(pin: pin, salt: salt).base64EncodedString())"
    }

    /// Constant-time comparison — no early exit on the first differing byte.
    /// Malformed blobs fail closed.
    static func verify(pin: String, stored: String) -> Bool {
        let parts = stored.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let salt = Data(base64Encoded: String(parts[0])),
              let expected = Data(base64Encoded: String(parts[1])) else { return false }
        let actual = digest(pin: pin, salt: salt)
        guard actual.count == expected.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(actual, expected) { diff |= a ^ b }
        return diff == 0
    }
}
