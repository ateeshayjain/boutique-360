import Foundation

enum GarmentType: String, Codable, CaseIterable, Identifiable {
    case blouse, kurti, lehenga, bottom, saree, suit, other
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// H9 fix: forward-compat decoder. If the DB returns a garment type we
    /// don't recognise (e.g. a future "anarkali"), fall back to .other rather
    /// than failing decode + losing the measurement record.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = GarmentType(rawValue: raw.lowercased()) ?? .other
    }
    var fields: [String] {
        switch self {
        case .blouse:  ["bust", "waist", "shoulder", "armhole", "sleeve_length", "blouse_length"]
        case .kurti:   ["chest", "waist", "hips", "length", "sleeve_length"]
        case .lehenga: ["waist", "hips", "length", "flare"]
        case .bottom:  ["waist", "hips", "length", "inseam"]
        case .saree:   ["blouse_bust", "blouse_waist", "fall_length"]
        case .suit:    ["chest", "waist", "hips", "length", "sleeve_length", "shoulder"]
        case .other:   []
        }
    }
}

struct CustomerMeasurement: Identifiable, Codable, Hashable {
    let id: UUID
    var customerId: UUID
    var boutiqueId: UUID
    var garmentType: String        // GarmentType.rawValue
    var measurementsJson: [String: Double]
    var takenAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case customerId = "customer_id"
        case boutiqueId = "boutique_id"
        case garmentType = "garment_type"
        case measurementsJson = "measurements_json"
        case takenAt = "taken_at"
    }
}

struct NewMeasurement: Encodable {
    let boutique_id: UUID
    let customer_id: UUID
    let garment_type: String
    let measurements_json: [String: Double]
}
