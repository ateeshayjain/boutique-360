import Foundation
import Combine
import Supabase
import Auth

/// Observable auth state. Restores session from the Supabase SDK's internal storage
/// on init, exposes sign-in / sign-out, and updates `session` reactively.
@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var isLoading: Bool = false
    @Published var lastError: String?

    private var task: Task<Void, Never>?

    init() {
        // Subscribe to auth state changes
        task = Task { [weak self] in
            guard let self else { return }
            for await change in SupabaseService.client.auth.authStateChanges {
                self.session = change.session
            }
        }
        // Restore current session synchronously if available
        Task { [weak self] in
            guard let self else { return }
            self.session = try? await SupabaseService.client.auth.session
        }
    }

    deinit { task?.cancel() }

    /// Send a magic-link to the given email. The user clicks it in their inbox and
    /// the universal/deep link returns them to the app via `handleAuthCallback`.
    func signInWithMagicLink(email: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            try await SupabaseService.client.auth.signInWithOTP(
                email: email,
                redirectTo: URL(string: "boutique360://auth/callback")
            )
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Process a magic-link callback URL.
    func handleAuthCallback(url: URL) async {
        do {
            try await SupabaseService.client.auth.session(from: url)
        } catch {
            lastError = "Sign-in callback failed: \(error.localizedDescription)"
        }
    }

    func signOut() async {
        do {
            try await SupabaseService.client.auth.signOut()
            self.session = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
