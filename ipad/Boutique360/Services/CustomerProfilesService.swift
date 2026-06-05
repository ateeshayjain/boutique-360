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

// Moved to Services/ImportantDatesService.swift
