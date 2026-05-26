import Foundation

/// Mirrors public.boutiques row.
struct Boutique: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let slug: String
    let gstin: String?
    let logoUrl: String?
    let brandColorHex: String?
    let address: String?           // multiline; used on invoices
    let placeOfSupply: String?     // state name for GST inter-state determination

    enum CodingKeys: String, CodingKey {
        case id, name, slug, gstin, address
        case logoUrl = "logo_url"
        case brandColorHex = "brand_color_hex"
        case placeOfSupply = "place_of_supply"
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
