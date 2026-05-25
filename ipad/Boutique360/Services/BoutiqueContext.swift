import Foundation
import Supabase

/// Provides the current user's boutique_id by querying their staff_users row.
/// Memoized for the lifetime of the auth session.
@MainActor
final class BoutiqueContext: ObservableObject {
    static let shared = BoutiqueContext()

    @Published private(set) var boutiqueId: UUID?
    @Published private(set) var staffName: String?
    @Published private(set) var staffRole: String?

    private init() {}

    /// Call after sign-in completes. Fetches staff_users row for current auth user.
    func refresh() async {
        do {
            struct StaffRow: Decodable {
                let boutique_id: UUID
                let name: String
                let role: String
            }
            let row: StaffRow = try await SupabaseService.client
                .from("staff_users")
                .select("boutique_id,name,role")
                .single()
                .execute()
                .value
            self.boutiqueId = row.boutique_id
            self.staffName = row.name
            self.staffRole = row.role
        } catch {
            self.boutiqueId = nil
            self.staffName = nil
            self.staffRole = nil
        }
    }

    func clear() {
        boutiqueId = nil
        staffName = nil
        staffRole = nil
    }
}
