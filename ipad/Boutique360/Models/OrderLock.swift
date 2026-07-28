import Foundation

/// R3 — the frozen contract for an order. Immutable once written (no update
/// path in app or service); post-lock changes live in ChangeOrder rows.
/// Breakup and buffer are historical artifacts: after a change order shifts
/// the order's totals or dates, the lock still records what was agreed at
/// lock time — the CO ledger records what changed since.
struct PriceBreakup: Codable, Hashable {
    var fabric: Double
    var work: Double
    var other: Double
    var sum: Double { fabric + work + other }
}

struct OrderLock: Identifiable, Codable, Hashable {
    let id: UUID
    var boutiqueId: UUID
    var orderId: UUID
    var designId: UUID?
    var renderImagePath: String?
    var fabricCode: String?
    var fabricDescription: String?
    var measurementId: UUID?
    var priceBreakup: PriceBreakup?
    var eventDate: String?            // frozen copies — YYYY-MM-DD
    var alterationBufferDays: Int?
    var mustFinishBy: String?
    var advanceAmount: Double
    var rushAccepted: Bool
    var lockedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case boutiqueId = "boutique_id"
        case orderId = "order_id"
        case designId = "design_id"
        case renderImagePath = "render_image_path"
        case fabricCode = "fabric_code"
        case fabricDescription = "fabric_description"
        case measurementId = "measurement_id"
        case priceBreakup = "price_breakup"
        case eventDate = "event_date"
        case alterationBufferDays = "alteration_buffer_days"
        case mustFinishBy = "must_finish_by"
        case advanceAmount = "advance_amount"
        case rushAccepted = "rush_accepted"
        case lockedAt = "locked_at"
    }
}

/// jsonb payload for the lock_order RPC.
struct NewOrderLock: Encodable {
    let boutique_id: UUID
    let order_id: UUID
    let design_id: UUID?
    let render_image_path: String?
    let fabric_code: String?
    let fabric_description: String?
    let measurement_id: UUID?
    let price_breakup: PriceBreakup?
    let event_date: String?
    let alteration_buffer_days: Int?
    let must_finish_by: String?
    let advance_amount: Double
    let rush_accepted: Bool
}

/// R3 — append-only spec-change record for a locked order. Applied via the
/// apply_change_order RPC, which atomically updates the order's totals and
/// event date. Never edited or deleted (DB policies enforce this) —
/// mistakes are corrected by a counter-CO.
struct ChangeOrder: Identifiable, Codable, Hashable {
    let id: UUID
    var boutiqueId: UUID
    var orderId: UUID
    var description: String
    var priceDelta: Double
    var newEventDate: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, description
        case boutiqueId = "boutique_id"
        case orderId = "order_id"
        case priceDelta = "price_delta"
        case newEventDate = "new_event_date"
        case createdAt = "created_at"
    }
}
