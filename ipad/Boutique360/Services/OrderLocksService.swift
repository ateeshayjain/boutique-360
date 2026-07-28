import Foundation
import Supabase

/// R3 — the frozen contract + its change-order ledger. Lock inserts go
/// through the lock_order RPC (atomic with the orders.design_id patch);
/// COs through apply_change_order (atomic totals/event update with
/// server-enforced lock precondition + subtotal floor).
enum OrderLocksService {
    static func get(orderId: UUID, boutiqueId: UUID) async throws -> OrderLock? {
        let rows: [OrderLock] = try await SupabaseService.client.from("order_locks")
            .select()
            .eq("boutique_id", value: boutiqueId)
            .eq("order_id", value: orderId)
            .limit(1)
            .execute().value
        return rows.first
    }

    static func lock(_ input: NewOrderLock) async throws -> OrderLock {
        struct P: Encodable { let p_lock: NewOrderLock }
        return try await SupabaseService.client
            .rpc("lock_order", params: P(p_lock: input))
            .execute().value
    }

    static func changeOrders(orderId: UUID, boutiqueId: UUID) async throws -> [ChangeOrder] {
        try await SupabaseService.client.from("change_orders")
            .select()
            .eq("boutique_id", value: boutiqueId)
            .eq("order_id", value: orderId)
            .order("created_at", ascending: false)
            .execute().value
    }

    static func applyChangeOrder(orderId: UUID, description: String,
                                 priceDelta: Double, newEventDate: String?) async throws -> ChangeOrder {
        struct P: Encodable {
            let p_order_id: UUID
            let p_description: String
            let p_price_delta: Double
            let p_new_event_date: String?
        }
        return try await SupabaseService.client
            .rpc("apply_change_order",
                 params: P(p_order_id: orderId, p_description: description,
                           p_price_delta: priceDelta, p_new_event_date: newEventDate))
            .execute().value
    }
}
