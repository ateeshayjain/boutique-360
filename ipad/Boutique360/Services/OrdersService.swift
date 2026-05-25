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
    static func create(
        order: NewOrder,
        items: [(productId: UUID?, variantId: UUID?, qty: Int, unitPrice: Double, gstAmount: Double)],
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
                    gst_amount: $0.gstAmount
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

    /// Invoice number: INV-YYYY-NNNN (per-year sequence). Naive sequence —
    /// queries today's count for the year. Good enough for single-boutique v1.
    static func generateOrderNumber() async throws -> String {
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        let prefix = "BTQ-\(year)-"
        struct CountRow: Decodable { let count: Int }
        let result: [Order] = try await SupabaseService.client.from("orders")
            .select("order_number")
            .like("order_number", pattern: "\(prefix)%")
            .execute()
            .value
        let next = result.count + 1
        return "\(prefix)\(String(format: "%04d", next))"
    }

    static func generateInvoiceNumber(forYear year: Int, existingCount: Int) -> String {
        "INV-\(year)-\(String(format: "%04d", existingCount + 1))"
    }
}
