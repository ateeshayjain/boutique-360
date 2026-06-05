import Foundation

/// Service wrapper for the `important_dates` table.
/// Extracted from inline Supabase calls in DashboardView + ImportantDatesListView
/// to honor the architecture layering rule: views never call the data layer directly.
enum ImportantDatesService {
    /// All important dates for a customer.
    static func listForCustomer(_ customerId: UUID) async throws -> [ImportantDate] {
        try await SupabaseService.client.from("important_dates")
            .select()
            .eq("customer_id", value: customerId)
            .order("date", ascending: true)
            .execute()
            .value
    }

    /// All important dates for the current boutique (RLS scopes by boutique).
    /// Defense-in-depth: also passes boutique_id filter explicitly.
    static func listForBoutique(_ boutiqueId: UUID) async throws -> [ImportantDate] {
        try await SupabaseService.client.from("important_dates")
            .select()
            .eq("boutique_id", value: boutiqueId)
            .execute()
            .value
    }

    static func create(_ input: NewImportantDate) async throws -> ImportantDate {
        try await SupabaseService.client.from("important_dates")
            .insert(input)
            .select()
            .single()
            .execute()
            .value
    }

    static func delete(_ id: UUID) async throws {
        _ = try await SupabaseService.client.from("important_dates")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
