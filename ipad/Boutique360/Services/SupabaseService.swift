import Foundation
import Supabase

/// Singleton Supabase client. Created lazily from Config; auth session is restored
/// from Keychain by the SDK on first access if a token was persisted.
enum SupabaseService {
    static let client: SupabaseClient = {
        SupabaseClient(
            supabaseURL: Config.supabaseURL,
            supabaseKey: Config.supabaseAnonKey
        )
    }()
}
