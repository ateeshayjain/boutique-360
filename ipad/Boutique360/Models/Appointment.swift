import Foundation

enum AppointmentType: String, Codable, CaseIterable, Identifiable, DecodableWithFallback {
    case fitting, consultation, delivery, pickup, other
    /// Upgrade-path fallback: `other` already means exactly this.
    static let decodingFallback: AppointmentType = .other
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .fitting: "person.crop.rectangle"
        case .consultation: "bubble.left.and.bubble.right"
        case .delivery: "shippingbox"
        case .pickup: "bag.fill"
        case .other: "calendar"
        }
    }
}

enum AppointmentStatus: String, Codable, CaseIterable, Identifiable, DecodableWithFallback {
    case scheduled, completed, cancelled, no_show
    /// Upgrade-path fallback: still on the calendar rather than silently completed.
    static let decodingFallback: AppointmentStatus = .scheduled
    var id: String { rawValue }
    var label: String {
        switch self {
        case .scheduled: "Scheduled"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        case .no_show: "No-show"
        }
    }
}

struct Appointment: Identifiable, Codable, Hashable {
    let id: UUID
    var boutiqueId: UUID
    var customerId: UUID
    var orderId: UUID?
    var type: AppointmentType
    var scheduledAt: Date
    var durationMinutes: Int
    var status: AppointmentStatus
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case id, type, status, notes
        case boutiqueId = "boutique_id"
        case customerId = "customer_id"
        case orderId = "order_id"
        case scheduledAt = "scheduled_at"
        case durationMinutes = "duration_minutes"
    }
}

struct NewAppointment: Encodable {
    let boutique_id: UUID
    let customer_id: UUID
    let order_id: UUID?
    let type: String
    let scheduled_at: String       // ISO8601
    let duration_minutes: Int
    let notes: String?
}
