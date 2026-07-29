import Foundation
import Supabase

/// R4a — the dedup ledger. Append-only at the DB (migration 0030 grants
/// select + insert only), so a handled reminder stays handled: there is no
/// code path, here or in the UI, that can un-handle one.
enum RemindersService {
    private struct Row: Decodable {
        let kind: String
        let subject_id: UUID
        let for_date: String
    }

    /// Keys for the window the drafts cover (today → tomorrow). Builds keys
    /// through `ReminderDrafts.key` so both sides share one format — the
    /// UUID case normalisation lives there and must not be duplicated.
    static func loggedKeys(boutiqueId: UUID, from: String, to: String) async throws -> Set<String> {
        let rows: [Row] = try await SupabaseService.client.from("reminder_log")
            .select("kind,subject_id,for_date")
            .eq("boutique_id", value: boutiqueId)
            .gte("for_date", value: from)
            .lte("for_date", value: to)
            .execute().value
        return Set(rows.compactMap { row in
            ReminderDrafts.Kind(rawValue: row.kind).map {
                ReminderDrafts.key(kind: $0, subjectId: row.subject_id, forDate: row.for_date)
            }
        })
    }

    /// Idempotent: the unique constraint makes a double-tap a 23505, which
    /// means "already handled" — the desired end state, not a failure.
    static func markDone(boutiqueId: UUID, kind: ReminderDrafts.Kind,
                         subjectId: UUID, forDate: String) async throws {
        struct NewRow: Encodable {
            let boutique_id: UUID
            let kind: String
            let subject_id: UUID
            let for_date: String
        }
        do {
            _ = try await SupabaseService.client.from("reminder_log")
                .insert(NewRow(boutique_id: boutiqueId, kind: kind.rawValue,
                               subject_id: subjectId, for_date: forDate))
                .execute()
        } catch let error as PostgrestError {
            // Prefer the typed code; the message check is only a fallback for
            // SDK versions that don't populate it. String-sniffing alone is
            // fragile.
            let isDuplicate = error.code == "23505"
                || error.message.lowercased().contains("duplicate key")
            guard isDuplicate else { throw error }
        }
    }
}
