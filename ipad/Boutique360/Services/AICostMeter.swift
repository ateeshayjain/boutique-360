import Foundation
import Supabase   // PostgrestError — needed to tell a real cap breach (P0001)
                  // apart from an infrastructure fault.

/// Per-boutique daily cost ceiling for AI calls. Server-side counter via
/// `record_ai_usage` RPC so the limit is tamper-proof from the iPad — a malicious
/// user can't reset by clearing UserDefaults.
///
/// The default cap is $5/day per boutique (≈ ₹420). At Gemini Flash pricing
/// that's ~5000 text calls or ~125 image renders — well above realistic daily
/// usage for a single boutique, but enough headroom that a stuck retry loop
/// would be caught before it racked bills.
///
/// Testing audit gap closed: "Token and cost limits enforced per user."
enum AICostMeter {
    /// Default daily cap in USD. Boutiques can override via a future per-boutique setting.
    static let defaultCapUSD: Double = 5.0

    /// Calls the Postgres function `record_ai_usage` which atomically increments
    /// the daily counter and raises if the cap is exceeded. The throw propagates
    /// to GeminiService.* callers, which already wrap in `phase = .failed(...)`.
    static func checkCeiling(costEstimate: Double) async throws {
        guard let bid = await BoutiqueContext.shared.boutiqueId else { return }
        struct P: Encodable {
            let p_boutique_id: UUID
            let p_cost_estimate_usd: Double
            let p_daily_cap_usd: Double
        }
        struct Result: Decodable {
            let calls_count: Int
            let cost_estimate_usd: Double
            let daily_cap_usd: Double
        }
        do {
            _ = try await SupabaseService.client
                .rpc("record_ai_usage", params: P(
                    p_boutique_id: bid,
                    p_cost_estimate_usd: costEstimate,
                    p_daily_cap_usd: defaultCapUSD
                ))
                .execute()
            Log.ai.debug("AI call accepted: cost $\(costEstimate, privacy: .public)")
        } catch {
            // 2026-07-31: this catch used to report EVERY failure as a cost
            // ceiling breach. `record_ai_usage` had been 403ing since it
            // shipped (RLS — see migration 0032), so every AI call failed and
            // the owner was told they'd hit a spending cap they had never
            // reached, and to wait until midnight, which fixed nothing.
            //
            // Only P0001 means the cap was genuinely reached; that is the
            // contract with the Postgres function. Anything else is a fault
            // and must say so, or the next infrastructure break will hide
            // behind the same misleading message.
            let isGenuineCeiling = (error as? PostgrestError)?.code == "P0001"
            Log.ai.error("record_ai_usage failed (ceiling=\(isGenuineCeiling, privacy: .public)) for boutique \(bid.uuidString, privacy: .public): \(error.localizedDescription, privacy: .private)")

            if isGenuineCeiling {
                throw NSError(domain: "AICostMeter", code: 429, userInfo: [
                    NSLocalizedDescriptionKey:
                        "Daily AI limit reached — try again after midnight, or raise the cap in Settings."
                ])
            }
            throw NSError(domain: "AICostMeter", code: 500, userInfo: [
                NSLocalizedDescriptionKey:
                    "Couldn't check the AI usage limit, so the request was not sent. This is a fault, not a spending cap — retry, and if it persists the AI features need attention."
            ])
        }
    }
}
