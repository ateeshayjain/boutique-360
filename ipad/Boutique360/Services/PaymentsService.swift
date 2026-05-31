import Foundation

/// Service wrapper for the `payments` table.
/// Extracted from inline Supabase calls in DashboardView + PaymentsSectionView
/// so views never reach into the SDK directly.
enum PaymentsService {
    struct CapturedRow: Decodable, Hashable {
        let amount: Double
        let method: String?
        let status: String
        let captured_at: Date?
    }

    struct PerOrderSum: Decodable, Hashable {
        let order_id: UUID
        let amount: Double
    }

    /// Today's captured revenue with method + timestamp — drives the "Today" card.
    static func capturedSinceMidnight() async throws -> [CapturedRow] {
        let isoMidnight = Formatters.iso8601Basic.string(from: Calendar.current.startOfDay(for: Date()))
        return try await SupabaseService.client.from("payments")
            .select("amount,method,status,captured_at")
            .eq("status", value: "captured")
            .gte("captured_at", value: isoMidnight)
            .execute()
            .value
    }

    /// Full payment history for a single order — drives PaymentsSectionView.
    struct OrderHistoryRow: Identifiable, Decodable {
        let id: UUID
        let amount: Double
        let status: String
        let method: String?
        let captured_at: Date?
        let created_at: Date
    }
    static func historyForOrder(_ orderId: UUID) async throws -> [OrderHistoryRow] {
        try await SupabaseService.client.from("payments")
            .select("id,amount,status,method,captured_at,created_at")
            .eq("order_id", value: orderId)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    /// Record a captured payment.
    struct NewPayment: Encodable {
        let boutique_id: UUID
        let order_id: UUID
        let amount: Double
        let status: String
        let method: String
        let captured_at: String
    }
    static func record(_ payment: NewPayment) async throws {
        _ = try await SupabaseService.client.from("payments")
            .insert(payment)
            .execute()
    }

    /// Single grouped query for a batch of order IDs — used by Dashboard overdue calc.
    /// Replaces the N-way waterfall (H5 fix).
    static func capturedSumsForOrders(_ orderIds: [UUID]) async throws -> [PerOrderSum] {
        guard !orderIds.isEmpty else { return [] }
        return try await SupabaseService.client.from("payments")
            .select("order_id,amount")
            .eq("status", value: "captured")
            .in("order_id", values: orderIds.map(\.uuidString))
            .execute()
            .value
    }
}
