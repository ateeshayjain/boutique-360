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
            // M1 fix: use central Formatters.iso8601Basic instead of allocating per call.
            patch["completed_at"] = Formatters.iso8601Basic.string(from: Date())
        }
        return try await SupabaseService.client.from("alterations")
            .update(patch)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    /// M12 fix: race-safe via `next_alteration_round` RPC (FOR UPDATE inside).
    /// The previous client-side max+1 had a TOCTOU race when two iPads added
    /// alteration requests against the same order simultaneously.
    static func nextRoundNumber(forOrder orderId: UUID) async throws -> Int {
        struct P: Encodable { let p_order_id: UUID }
        return try await SupabaseService.client
            .rpc("next_alteration_round", params: P(p_order_id: orderId))
            .execute()
            .value
    }
}
