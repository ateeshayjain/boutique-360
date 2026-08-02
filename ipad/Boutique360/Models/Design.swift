import Foundation

enum DesignStatus: String, Codable, CaseIterable, Identifiable, DecodableWithFallback {
    case draft, rendered, shared_with_customer, approved, in_production, delivered, archived
    /// Upgrade-path fallback: never implies shared-with-customer or approved.
    static let decodingFallback: DesignStatus = .draft
    var id: String { rawValue }
    var label: String {
        switch self {
        case .draft: "Draft"
        case .rendered: "Rendered"
        case .shared_with_customer: "Shared"
        case .approved: "Approved"
        case .in_production: "In production"
        case .delivered: "Delivered"
        case .archived: "Archived"
        }
    }
    var tint: String {
        switch self {
        case .draft: "gray"
        case .rendered: "indigo"
        case .shared_with_customer: "purple"
        case .approved: "blue"
        case .in_production: "orange"
        case .delivered: "green"
        case .archived: "secondary"
        }
    }
}

struct Design: Identifiable, Codable, Hashable {
    let id: UUID
    var boutiqueId: UUID
    var customerId: UUID?
    var name: String
    var status: DesignStatus
    var sketchImageUrl: String?         // deprecated: short-lived signed URL, may be expired
    var sketchImagePath: String?        // canonical path inside design-sketches bucket
    var referenceImagePath: String?     // canonical path inside design-references bucket
    var measurementsJson: [String: Double]?
    var garmentType: String?
    var occasion: String?
    var notesMd: String?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, status, occasion
        case boutiqueId = "boutique_id"
        case customerId = "customer_id"
        case sketchImageUrl = "sketch_image_url"
        case sketchImagePath = "sketch_image_path"
        case referenceImagePath = "reference_image_path"
        case measurementsJson = "measurements_json"
        case garmentType = "garment_type"
        case notesMd = "notes_md"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct NewDesign: Encodable {
    let boutique_id: UUID
    let customer_id: UUID?
    let name: String
    let status: String
    let garment_type: String?
    let occasion: String?
    let notes_md: String?
    let created_by_staff_id: UUID?
}

enum LookbookVisibility: String, Codable, CaseIterable, Identifiable, DecodableWithFallback {
    case staff_only, customer_shared, public_visible
    /// Upgrade-path fallback: most private option — an unknown visibility must never widen exposure.
    static let decodingFallback: LookbookVisibility = .staff_only
    var id: String { rawValue }
    var label: String {
        switch self {
        case .staff_only: "Staff only"
        case .customer_shared: "Share with customers"
        case .public_visible: "Public"
        }
    }
}

struct DesignLookbook: Identifiable, Codable, Hashable {
    let id: UUID
    var boutiqueId: UUID
    var name: String
    var coverImageUrl: String?
    var description: String?
    var visibleTo: String

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case boutiqueId = "boutique_id"
        case coverImageUrl = "cover_image_url"
        case visibleTo = "visible_to"
    }
}

struct NewLookbook: Encodable {
    let boutique_id: UUID
    let name: String
    let description: String?
    let visible_to: String
}
