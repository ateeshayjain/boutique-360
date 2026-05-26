import Foundation

enum RenderStatus: String, Codable, CaseIterable {
    case queued, done, failed
}

struct DesignRender: Identifiable, Codable, Hashable {
    let id: UUID
    var boutiqueId: UUID
    var designId: UUID
    var promptUsed: String?
    var resultImageUrl: String?
    var modelUsed: String?
    var processingMs: Int?
    var costEstimateUsd: Double?
    var status: RenderStatus
    var errorMsg: String?
    var isFavorite: Bool
    var parentRenderId: UUID?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status
        case boutiqueId = "boutique_id"
        case designId = "design_id"
        case promptUsed = "prompt_used"
        case resultImageUrl = "result_image_url"
        case modelUsed = "model_used"
        case processingMs = "processing_ms"
        case costEstimateUsd = "cost_estimate_usd"
        case errorMsg = "error_msg"
        case isFavorite = "is_favorite"
        case parentRenderId = "parent_render_id"
        case createdAt = "created_at"
    }
}

struct NewDesignRender: Encodable {
    let boutique_id: UUID
    let design_id: UUID
    let prompt_used: String
    let result_image_url: String?
    let model_used: String
    let processing_ms: Int
    let cost_estimate_usd: Double
    let status: String
    let error_msg: String?
}

struct DesignTryOn: Identifiable, Codable, Hashable {
    let id: UUID
    var boutiqueId: UUID
    var designRenderId: UUID
    var customerId: UUID
    var customerPhotoUrl: String?
    var resultImageUrl: String?
    var modelUsed: String?
    var processingMs: Int?
    var costEstimateUsd: Double?
    var customerConsentSignedAt: Date
    var savedToLookbook: Bool
    var createdAt: Date
    var purgeAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case boutiqueId = "boutique_id"
        case designRenderId = "design_render_id"
        case customerId = "customer_id"
        case customerPhotoUrl = "customer_photo_url"
        case resultImageUrl = "result_image_url"
        case modelUsed = "model_used"
        case processingMs = "processing_ms"
        case costEstimateUsd = "cost_estimate_usd"
        case customerConsentSignedAt = "customer_consent_signed_at"
        case savedToLookbook = "saved_to_lookbook"
        case createdAt = "created_at"
        case purgeAt = "purge_at"
    }
}

struct NewDesignTryOn: Encodable {
    let boutique_id: UUID
    let design_render_id: UUID
    let customer_id: UUID
    let customer_photo_url: String?
    let result_image_url: String?
    let model_used: String
    let processing_ms: Int
    let cost_estimate_usd: Double
    let customer_consent_signed_at: String   // ISO8601
    let saved_to_lookbook: Bool
}
