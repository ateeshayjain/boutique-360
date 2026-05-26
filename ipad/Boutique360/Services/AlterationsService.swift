import Foundation
import Supabase

enum AlterationsService {
    static func listForOrder(_ orderId: UUID) async throws -> [Alteration] {
        try await SupabaseService.client.from("alterations")
            .select()
            .eq("order_id", value: orderId)
            .order("round_number", ascending: true)
            .execute()
            .value
    }

    static func create(_ input: NewAlteration) async throws -> Alteration {
        try await SupabaseService.client.from("alterations")
            .insert(input)
            .select()
            .single()
            .execute()
            .value
    }

    static func updateStatus(_ id: UUID, to status: AlterationStatus, completed: Bool = false) async throws -> Alteration {
        var patch: [String: String] = ["status": status.rawValue]
        if completed {
            patch["completed_at"] = ISO8601DateFormatter().string(from: Date())
        }
        return try await SupabaseService.client.from("alterations")
            .update(patch)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    static func nextRoundNumber(forOrder orderId: UUID) async throws -> Int {
        let existing = try await listForOrder(orderId)
        return (existing.map(\.roundNumber).max() ?? 0) + 1
    }
}
