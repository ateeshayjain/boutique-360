import Foundation
import Supabase

enum JobCardsService {
    static func list(status: JobCardStatus? = nil) async throws -> [JobCard] {
        var query = SupabaseService.client.from("job_cards").select()
        if let s = status { query = query.eq("status", value: s.rawValue) }
        return try await query.order("created_at", ascending: false).limit(200).execute().value
    }

    static func get(id: UUID) async throws -> JobCard {
        try await SupabaseService.client.from("job_cards")
            .select().eq("id", value: id).single().execute().value
    }

    static func listForDesign(_ designId: UUID) async throws -> [JobCard] {
        try await SupabaseService.client.from("job_cards")
            .select().eq("design_id", value: designId).order("created_at").execute().value
    }

    /// Customer-scoped fetch. Lets the timeline aggregator avoid pulling every
    /// job card and filtering client-side as the boutique grows.
    static func listForCustomer(_ customerId: UUID) async throws -> [JobCard] {
        try await SupabaseService.client.from("job_cards")
            .select()
            .eq("customer_id", value: customerId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    static func create(_ input: NewJobCard) async throws -> JobCard {
        try await SupabaseService.client.from("job_cards")
            .insert(input).select().single().execute().value
    }

    /// Race-safe per-boutique job number via the same RPC orders use.
    static func generateJobNumber(boutiqueId: UUID) async throws -> String {
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        struct P: Encodable { let p_boutique_id: UUID; let p_sequence_name: String }
        let next: Int64 = try await SupabaseService.client
            .rpc("next_sequence_value", params: P(p_boutique_id: boutiqueId, p_sequence_name: "jobcards-\(year)"))
            .execute().value
        return "JC-\(year)-\(String(format: "%04d", next))"
    }

    /// Fetch the configured workshop stages for this boutique.
    /// Returns the default 7-stage flow if no per-boutique config exists.
    static func workshopStages(boutiqueId: UUID) async throws -> [String] {
        struct Row: Decodable { let value_json: [String]? }
        let rows: [Row] = try await SupabaseService.client.from("settings")
            .select("value_json")
            .eq("boutique_id", value: boutiqueId)
            .eq("key", value: "workshop_stages")
            .execute().value
        return rows.first?.value_json ?? ["Cutting","Stitching","Embroidery","Trial fitting","Finishing","QC","Ready"]
    }
}
