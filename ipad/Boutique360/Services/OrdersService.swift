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

    /// Creates an order header + items in one logical call.
    /// Pre-condition: caller has computed totals correctly.
    struct LineDraft {
        let productId: UUID?
        let variantId: UUID?
        let qty: Int
        let unitPrice: Double
        let gstRate: Double?   // H13 fix: explicit per-line rate
        let gstAmount: Double
        let lineDescription: String?
    }
    /// B6 fix: atomic via `create_order_with_items` RPC. The Postgres function
    /// runs header + items + inquiry-link in a single transaction — any failure
    /// rolls back the whole thing, no more orphan order headers or unconverted
    /// inquiries on partial failure.
    static func create(
        order: NewOrder,
        items: [LineDraft],
        sourceInquiryId: UUID? = nil
    ) async throws -> Order {
        struct RPCParams: Encodable {
            let p_order: NewOrder
            let p_items: [LineDraftEncodable]
            let p_source_inquiry_id: UUID?
        }
        struct LineDraftEncodable: Encodable {
            let boutique_id: UUID
            let product_id: UUID?
            let variant_id: UUID?
            let qty: Int
            let unit_price: Double
            let gst_rate: Double?
            let gst_amount: Double
            let line_description: String?
        }
        let encodableItems = items.map {
            LineDraftEncodable(
                boutique_id: order.boutique_id,
                product_id: $0.productId,
                variant_id: $0.variantId,
                qty: $0.qty,
                unit_price: $0.unitPrice,
                gst_rate: $0.gstRate,
                gst_amount: $0.gstAmount,
                line_description: $0.lineDescription
            )
        }
        let params = RPCParams(
            p_order: order,
            p_items: encodableItems,
            p_source_inquiry_id: sourceInquiryId
        )
        return try await SupabaseService.client
            .rpc("create_order_with_items", params: params)
            .execute()
            .value
    }

    static func updateStatus(_ id: UUID, to status: OrderStatus) async throws -> Order {
        let updated: Order = try await SupabaseService.client.from("orders")
            .update(["status": status.rawValue])
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
        // Business event — useful for analytics + debugging "where did this order go?"
        Log.business.notice("order \(updated.orderNumber, privacy: .public) → \(status.rawValue, privacy: .public)")
        return updated
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
