import Foundation

struct Customer: Identifiable, Codable, Hashable {
    let id: UUID
    var boutiqueId: UUID
    var name: String
    var phone: String?
    var email: String?
    var dob: String?              // YYYY-MM-DD; left as string for simplicity
    var tags: [String]
    var vipStatus: Bool
    var loyaltyPoints: Int
    var currentTierId: UUID?
    var source: String
    var consentWhatsapp: Bool
    var consentEmail: Bool
    var notes: String?            // not in DB yet — derived from style_notes_md via profile (deferred)
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, phone, email, dob, tags, source, notes
        case boutiqueId = "boutique_id"
        case vipStatus = "vip_status"
        case loyaltyPoints = "loyalty_points"
        case currentTierId = "current_tier_id"
        case consentWhatsapp = "consent_whatsapp"
        case consentEmail = "consent_email"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var displayPhone: String { phone ?? "—" }
    var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

/// For inserts where DB provides defaults.
struct NewCustomer: Encodable {
    let boutique_id: UUID
    let name: String
    let phone: String?
    let email: String?
    let dob: String?
    let tags: [String]
    let vip_status: Bool
    let source: String
    let consent_whatsapp: Bool
    let consent_email: Bool
}
