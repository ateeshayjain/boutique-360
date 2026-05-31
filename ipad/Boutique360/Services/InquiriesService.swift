import Foundation
import Supabase

enum InquiriesService {
    static func list(status: InquiryStatus? = nil, customerId: UUID? = nil) async throws -> [Inquiry] {
        var query = SupabaseService.client.from("inquiries").select()
        if let s = status {
            query = query.eq("status", value: s.rawValue)
        }
        if let cid = customerId {
            query = query.eq("customer_id", value: cid)
        }
        return try await query
            .order("created_at", ascending: false)
            .limit(200)
            .execute()
            .value
    }

    static func create(_ input: NewInquiry) async throws -> Inquiry {
        try await SupabaseService.client.from("inquiries")
            .insert(input)
            .select()
            .single()
            .execute()
            .value
    }

    static func updateStatus(_ id: UUID, to status: InquiryStatus) async throws -> Inquiry {
        try await SupabaseService.client.from("inquiries")
            .update(["status": status.rawValue])
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    /// L6 fix: race-safe via `next_sequence_value` RPC instead of `Int.random`.
    /// Birthday paradox: ~40% collision probability at 100 inquiries/month.
    /// Same pattern orders/jobcards already use.
    static func generateInquiryNumber(boutiqueId: UUID) async throws -> String {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month], from: Date())
        let yyyymm = String(format: "%04d%02d", comps.year ?? 2026, comps.month ?? 1)
        struct P: Encodable {
            let p_boutique_id: UUID
            let p_sequence_name: String
        }
        let next: Int64 = try await SupabaseService.client
            .rpc("next_sequence_value", params: P(p_boutique_id: boutiqueId, p_sequence_name: "inquiries-\(yyyymm)"))
            .execute()
            .value
        return "INQ-\(yyyymm)-\(String(format: "%04d", next))"
    }
}
