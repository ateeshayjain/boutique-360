import Foundation
import Supabase

enum MeasurementsService {
    static func listForCustomer(_ customerId: UUID) async throws -> [CustomerMeasurement] {
        try await SupabaseService.client.from("customer_measurements")
            .select()
            .eq("customer_id", value: customerId)
            .order("taken_at", ascending: false)
            .execute()
            .value
    }

    static func create(_ input: NewMeasurement) async throws -> CustomerMeasurement {
        try await SupabaseService.client.from("customer_measurements")
            .insert(input)
            .select()
            .single()
            .execute()
            .value
    }
}
