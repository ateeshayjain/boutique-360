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

    static func generateInquiryNumber() -> String {
        // INQ-YYYYMM-NNNN (random 4-digit; collision-safe enough for a single boutique)
        let f = DateFormatter()
        f.dateFormat = "yyyyMM"
        let suffix = String(format: "%04d", Int.random(in: 0...9999))
        return "INQ-\(f.string(from: Date()))-\(suffix)"
    }
}
