import Foundation
import Supabase

enum CustomerProfilesService {
    static func get(customerId: UUID) async throws -> CustomerProfile? {
        let rows: [CustomerProfile] = try await SupabaseService.client
            .from("customer_profiles")
            .select()
            .eq("customer_id", value: customerId)
            .execute()
            .value
        return rows.first
    }

    /// Upserts the profile row. Creates if missing; updates if present.
    static func upsert(_ profile: CustomerProfile) async throws -> CustomerProfile {
        try await SupabaseService.client
            .from("customer_profiles")
            .upsert(profile, onConflict: "customer_id")
            .select()
            .single()
            .execute()
            .value
    }
}

enum ImportantDatesService {
    static func listForCustomer(_ customerId: UUID) async throws -> [ImportantDate] {
        try await SupabaseService.client.from("important_dates")
            .select()
            .eq("customer_id", value: customerId)
            .order("date", ascending: true)
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
