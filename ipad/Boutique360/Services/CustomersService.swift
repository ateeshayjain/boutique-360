import Foundation
import Supabase

enum CustomersService {
    static func list(searchQuery: String? = nil, limit: Int = 200) async throws -> [Customer] {
        let table = SupabaseService.client.from("customers")
        var query = table.select().is("deleted_at", value: nil)
        if let raw = searchQuery {
            let q = raw.trimmingCharacters(in: .whitespaces)
            if !q.isEmpty {
                // Escape % and , as they have special meaning in PostgREST or() / ilike
                let safe = q.replacingOccurrences(of: ",", with: "")
                            .replacingOccurrences(of: "%", with: "")
                query = query.or("name.ilike.%\(safe)%,phone.ilike.%\(safe)%,email.ilike.%\(safe)%")
            }
        }
        return try await query
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    static func get(id: UUID) async throws -> Customer {
        try await SupabaseService.client.from("customers")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    static func create(_ input: NewCustomer) async throws -> Customer {
        try await SupabaseService.client.from("customers")
            .insert(input)
            .select()
            .single()
            .execute()
            .value
    }

    static func update(_ id: UUID, patch: CustomerPatch) async throws -> Customer {
        try await SupabaseService.client.from("customers")
            .update(patch)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    struct CustomerPatch: Encodable {
        var name: String?
        var phone: String?
        var email: String?
        var dob: String?
        var vip_status: Bool?
        var consent_whatsapp: Bool?
        var consent_email: Bool?
        var source: String?
        var tags: [String]?
    }

    static func softDelete(_ id: UUID) async throws {
        let now = Formatters.iso8601Basic.string(from: Date())
        _ = try await SupabaseService.client.from("customers")
            .update(["deleted_at": now])
            .eq("id", value: id)
            .execute()
    }
}
