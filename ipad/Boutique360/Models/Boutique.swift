import Foundation

/// Mirrors public.boutiques row.
struct Boutique: Identifiable, Decodable, Hashable {
    let id: UUID
    let name: String
    let slug: String
    let gstin: String?
    let logoUrl: String?
    let brandColorHex: String?

    enum CodingKeys: String, CodingKey {
        case id, name, slug, gstin
        case logoUrl = "logo_url"
        case brandColorHex = "brand_color_hex"
    }
}

/// Mirrors public.loyalty_tiers row.
struct LoyaltyTier: Identifiable, Decodable, Hashable {
    let id: UUID
    let name: String
    let colorHex: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case colorHex = "color_hex"
        case sortOrder = "sort_order"
    }
}
