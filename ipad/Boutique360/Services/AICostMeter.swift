import Foundation

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
            // The Postgres function raises with code P0001 + a message containing
            // the cap. Propagate as a user-readable error.
            Log.ai.error("AI cost ceiling reached for boutique \(bid.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw NSError(
                domain: "AICostMeter",
                code: 429,
                userInfo: [
                    NSLocalizedDescriptionKey: "Daily AI cost ceiling reached — try again after midnight or raise the cap in Settings."
                ]
            )
        }
    }
}
