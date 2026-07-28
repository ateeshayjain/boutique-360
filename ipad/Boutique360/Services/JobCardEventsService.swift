import Foundation
import Supabase

/// R4d — karigar progress events (inserted by the job-card-view Edge
/// Function; read + token management from the iPad).
enum JobCardEventsService {
    static func list(jobCardId: UUID, boutiqueId: UUID) async throws -> [JobCardEvent] {
        try await SupabaseService.client.from("job_card_events")
            .select()
            .eq("boutique_id", value: boutiqueId)
            .eq("job_card_id", value: jobCardId)
            .order("created_at", ascending: false)
            .execute().value
    }

    /// Batch for list badges: events for a page of cards, newest first.
    static func forJobCards(_ ids: [UUID], boutiqueId: UUID) async throws -> [JobCardEvent] {
        guard !ids.isEmpty else { return [] }
        return try await SupabaseService.client.from("job_card_events")
            .select()
            .eq("boutique_id", value: boutiqueId)
            .in("job_card_id", values: ids)
            .order("created_at", ascending: false)
            .execute().value
    }

    /// Revokes previously shared links by rotating the capability token.
    static func regenerateToken(jobCardId: UUID) async throws -> UUID {
        struct Row: Decodable { let share_token: UUID }
        let row: Row = try await SupabaseService.client.from("job_cards")
            .update(["share_token": UUID().uuidString])
            .eq("id", value: jobCardId)
            .select("share_token").single().execute().value
        return row.share_token
    }

    static func shareURL(token: UUID) -> URL {
        Config.supabaseURL
            .appendingPathComponent("functions/v1/job-card-view/\(token.uuidString.lowercased())")
    }
}
