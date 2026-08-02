import Foundation

enum RenderStatus: String, Codable, CaseIterable, DecodableWithFallback {
    case queued, done, failed
    /// Upgrade-path fallback: never claim a render succeeded when we can't tell.
    static let decodingFallback: RenderStatus = .failed
}

struct DesignRender: Identifiable, Codable, Hashable {
    let id: UUID
    var boutiqueId: UUID
    var designId: UUID
    var promptUsed: String?
    var resultImageUrl: String?           // deprecated: short-lived signed URL
    var resultImagePath: String?          // canonical path inside design-renders bucket
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
        case resultImagePath = "result_image_path"
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
    let result_image_path: String?
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
    var customerPhotoUrl: String?     // deprecated: 1-hr signed URL, use customerPhotoPath
    var customerPhotoPath: String?    // canonical path inside customer-photos bucket
    var resultImageUrl: String?       // public-bucket URL — stable, but path is source of truth
    var resultImagePath: String?      // canonical path inside vto-results bucket
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
        case customerPhotoPath = "customer_photo_path"
        case resultImageUrl = "result_image_url"
        case resultImagePath = "result_image_path"
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
    // URLs intentionally omitted on insert — only paths are persisted. Signed URLs
    // are regenerated at view time via StorageService.signedURL(bucket:path:).
    let customer_photo_path: String
    let result_image_path: String
    let model_used: String
    let processing_ms: Int
    let cost_estimate_usd: Double
    let customer_consent_signed_at: String   // ISO8601, captured at moment of consent
    let saved_to_lookbook: Bool
}
