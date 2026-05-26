import Foundation
import Supabase

enum OrdersService {
    static func list(status: OrderStatus? = nil, customerId: UUID? = nil) async throws -> [Order] {
        var query = SupabaseService.client.from("orders").select()
        if let s = status { query = query.eq("status", value: s.rawValue) }
        if let cid = customerId { query = query.eq("customer_id", value: cid) }
        return try await query
            .order("created_at", ascending: false)
            .limit(200)
            .execute()
            .value
    }

    static func get(id: UUID) async throws -> Order {
        try await SupabaseService.client.from("orders")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    static func items(forOrder orderId: UUID) async throws -> [OrderItem] {
        try await SupabaseService.client.from("order_items")
            .select()
            .eq("order_id", value: orderId)
            .execute()
            .value
    }

    /// Creates an order header + items in one logical call (two requests).
    /// Pre-condition: caller has computed totals correctly.
    struct LineDraft {
        let productId: UUID?
        let variantId: UUID?
        let qty: Int
        let unitPrice: Double
        let gstAmount: Double
        let lineDescription: String?
    }
    static func create(
        order: NewOrder,
        items: [LineDraft],
        sourceInquiryId: UUID? = nil
    ) async throws -> Order {
        let created: Order = try await SupabaseService.client.from("orders")
            .insert(order)
            .select()
            .single()
            .execute()
            .value

        if !items.isEmpty {
            let rows = items.map {
                NewOrderItem(
                    order_id: created.id,
                    boutique_id: order.boutique_id,
                    product_id: $0.productId,
                    variant_id: $0.variantId,
                    qty: $0.qty,
                    unit_price: $0.unitPrice,
                    gst_amount: $0.gstAmount,
                    line_description: $0.lineDescription
                )
            }
            _ = try await SupabaseService.client.from("order_items").insert(rows).execute()
        }

        // If converted from an inquiry, link it bi-directionally
        if let inqId = sourceInquiryId {
            _ = try await SupabaseService.client.from("inquiries")
                .update(["converted_order_id": created.id.uuidString, "status": "confirmed"])
                .eq("id", value: inqId)
                .execute()
        }
        return created
    }

    static func updateStatus(_ id: UUID, to status: OrderStatus) async throws -> Order {
        try await SupabaseService.client.from("orders")
            .update(["status": status.rawValue])
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    /// Race-safe per-boutique sequence via Postgres RPC. Replaces the prior
    /// `count + 1` pattern which two concurrent iPads could collide on.
    static func generateOrderNumber(boutiqueId: UUID) async throws -> String {
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        struct RPCParams: Encodable {
            let p_boutique_id: UUID
            let p_sequence_name: String
        }
        let next: Int64 = try await SupabaseService.client
            .rpc("next_sequence_value", params: RPCParams(p_boutique_id: boutiqueId, p_sequence_name: "orders-\(year)"))
            .execute()
            .value
        return "BTQ-\(year)-\(String(format: "%04d", next))"
    }
}
