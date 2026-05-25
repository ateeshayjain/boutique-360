import Foundation

enum StylePersona: String, Codable, CaseIterable, Identifiable {
    case traditional, fusion, modern, minimalist, maximalist
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .traditional: "leaf"
        case .fusion:      "circle.lefthalf.filled"
        case .modern:      "square.fill"
        case .minimalist:  "circle"
        case .maximalist:  "sparkles"
        }
    }
}

enum BodyType: String, Codable, CaseIterable, Identifiable {
    case pear, apple, hourglass, rectangle, inverted_triangle
    var id: String { rawValue }
    var label: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}

enum SkinTone: String, Codable, CaseIterable, Identifiable {
    case fair, wheatish, dusky, deep
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum BudgetBand: String, Codable, CaseIterable, Identifiable {
    case value, mid, premium, luxury
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct CustomerProfile: Codable, Hashable {
    var customerId: UUID
    var boutiqueId: UUID
    var stylePersona: String?
    var colorPalette: [String]
    var fabricPreferences: [String]
    var avoidFabrics: [String]
    var bodyType: String?
    var heightCm: Int?
    var skinTone: String?
    var budgetBand: String?
    var favoriteDesigners: [String]
    var pinterestUrl: String?
    var instagramHandle: String?
    var styleNotesMd: String?

    enum CodingKeys: String, CodingKey {
        case customerId = "customer_id"
        case boutiqueId = "boutique_id"
        case stylePersona = "style_persona"
        case colorPalette = "color_palette"
        case fabricPreferences = "fabric_preferences"
        case avoidFabrics = "avoid_fabrics"
        case bodyType = "body_type"
        case heightCm = "height_cm"
        case skinTone = "skin_tone"
        case budgetBand = "budget_band"
        case favoriteDesigners = "favorite_designers"
        case pinterestUrl = "pinterest_url"
        case instagramHandle = "instagram_handle"
        case styleNotesMd = "style_notes_md"
    }
}

struct ImportantDate: Identifiable, Codable, Hashable {
    let id: UUID
    var boutiqueId: UUID
    var customerId: UUID
    var occasion: String
    var date: String                  // YYYY-MM-DD
    var recurring: Bool
    var reminderDaysBefore: Int

    enum CodingKeys: String, CodingKey {
        case id, occasion, date, recurring
        case boutiqueId = "boutique_id"
        case customerId = "customer_id"
        case reminderDaysBefore = "reminder_days_before"
    }
}

struct NewImportantDate: Encodable {
    let boutique_id: UUID
    let customer_id: UUID
    let occasion: String
    let date: String
    let recurring: Bool
    let reminder_days_before: Int
}
