import Foundation

/// Read/write operations on the `boutiques` row.
/// BoutiqueContext (the @MainActor session-cache) is the live source for the
/// current boutique; this service is for writes + ad-hoc reads.
enum BoutiqueService {
    struct Patch: Encodable {
        let name: String
        let gstin: String?
        let place_of_supply: String?
        let address: String?
    }

    /// Update the boutique row. Caller is responsible for calling `BoutiqueContext.refresh()`
    /// after a successful update so the rest of the app sees the new values.
    static func update(id: UUID, patch: Patch) async throws {
        _ = try await SupabaseService.client.from("boutiques")
            .update(patch)
            .eq("id", value: id)
            .execute()
    }
}
