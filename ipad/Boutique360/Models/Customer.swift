import Foundation

/// Structured customer address. Stored as JSONB in `customers.address_json`.
/// Every field is optional so partial captures (e.g. just city + PIN) round-trip
/// cleanly. The PIN field is a free-form string (not numeric) because Indian
/// PINs are 6 digits but pre-fill UX often deals with partials.
struct Address: Codable, Hashable, Equatable {
    var line1: String?
    var line2: String?
    var city: String?
    var state: String?
    var pin: String?
    var country: String?

    var isEmpty: Bool {
        (line1?.isEmpty ?? true) && (line2?.isEmpty ?? true) &&
        (city?.isEmpty ?? true) && (state?.isEmpty ?? true) &&
        (pin?.isEmpty ?? true) && (country?.isEmpty ?? true)
    }

    /// Human-readable single-line form for invoices / share sheets.
    /// Skips empty parts so a partial address still renders sensibly.
    var oneLine: String {
        [line1, line2, city, state, pin, country]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Multi-line form (one component per line) for PDF/invoice layout.
    var multiLine: String {
        var lines: [String] = []
        if let l1 = line1?.trimmingCharacters(in: .whitespaces), !l1.isEmpty { lines.append(l1) }
        if let l2 = line2?.trimmingCharacters(in: .whitespaces), !l2.isEmpty { lines.append(l2) }
        let cityState = [city, state].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let cityStatePin = cityState + [pin?.trimmingCharacters(in: .whitespaces)].compactMap { $0 }.filter { !$0.isEmpty }
        if !cityStatePin.isEmpty { lines.append(cityStatePin.joined(separator: " ")) }
        if let c = country?.trimmingCharacters(in: .whitespaces), !c.isEmpty { lines.append(c) }
        return lines.joined(separator: "\n")
    }
}

struct Customer: Identifiable, Codable, Hashable {
    let id: UUID
    var boutiqueId: UUID
    var name: String
    var phone: String?
    var whatsappPhone: String?      // 0027: separate WA number; falls back to phone at read time
    var email: String?
    var dob: String?                // YYYY-MM-DD; left as string for simplicity
    var address: Address?           // address_json JSONB — schema since 0006, exposed here in Wave 1
    var tags: [String]
    var vipStatus: Bool
    var loyaltyPoints: Int
    var currentTierId: UUID?
    var source: String
    var consentWhatsapp: Bool
    var consentEmail: Bool
    var notes: String?              // not in DB yet — derived from style_notes_md via profile (deferred)
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, phone, email, dob, tags, source, notes
        case boutiqueId = "boutique_id"
        case whatsappPhone = "whatsapp_phone"
        case address = "address_json"
        case vipStatus = "vip_status"
        case loyaltyPoints = "loyalty_points"
        case currentTierId = "current_tier_id"
        case consentWhatsapp = "consent_whatsapp"
        case consentEmail = "consent_email"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var displayPhone: String { phone ?? "—" }

    /// What the WhatsApp share helper / SMS sender should target. Prefer the
    /// explicit WA number; fall back to phone so existing customers continue
    /// to work without an edit. Returns nil if neither is present.
    var whatsappTarget: String? {
        if let wa = whatsappPhone?.trimmingCharacters(in: .whitespaces), !wa.isEmpty { return wa }
        return phone?.trimmingCharacters(in: .whitespaces).nonEmpty
    }

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// For inserts where DB provides defaults.
struct NewCustomer: Encodable {
    let boutique_id: UUID
    let name: String
    let phone: String?
    let whatsapp_phone: String?
    let email: String?
    let dob: String?
    let address_json: Address?
    let tags: [String]
    let vip_status: Bool
    let source: String
    let consent_whatsapp: Bool
    let consent_email: Bool
}
