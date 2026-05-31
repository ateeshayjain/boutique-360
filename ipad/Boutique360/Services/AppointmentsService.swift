import Foundation
import Supabase

enum AppointmentsService {
    static func list(from: Date? = nil, to: Date? = nil) async throws -> [Appointment] {
        var query = SupabaseService.client.from("appointments").select()
        // M1 fix: use central Formatters.iso8601Basic.
        if let f = from { query = query.gte("scheduled_at", value: Formatters.iso8601Basic.string(from: f)) }
        if let t = to   { query = query.lt("scheduled_at",  value: Formatters.iso8601Basic.string(from: t)) }
        return try await query
            .order("scheduled_at", ascending: true)
            .limit(500)
            .execute()
            .value
    }

    static func listForCustomer(_ customerId: UUID) async throws -> [Appointment] {
        try await SupabaseService.client.from("appointments")
            .select()
            .eq("customer_id", value: customerId)
            .order("scheduled_at", ascending: false)
            .execute()
            .value
    }

    static func listForOrder(_ orderId: UUID) async throws -> [Appointment] {
        try await SupabaseService.client.from("appointments")
            .select()
            .eq("order_id", value: orderId)
            .order("scheduled_at", ascending: true)
            .execute()
            .value
    }

    static func create(_ input: NewAppointment) async throws -> Appointment {
        try await SupabaseService.client.from("appointments")
            .insert(input)
            .select()
            .single()
            .execute()
            .value
    }

    static func updateStatus(_ id: UUID, to status: AppointmentStatus) async throws -> Appointment {
        try await SupabaseService.client.from("appointments")
            .update(["status": status.rawValue])
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }
}
