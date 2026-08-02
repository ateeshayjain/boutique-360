import Foundation

enum AlterationStatus: String, Codable, CaseIterable, Identifiable, DecodableWithFallback {
    case requested, in_progress, completed, cancelled
    /// Upgrade-path fallback: open, not completed.
    static let decodingFallback: AlterationStatus = .requested
    var id: String { rawValue }
    var label: String {
        switch self {
        case .requested: "Requested"
        case .in_progress: "In progress"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        }
    }
    var systemImage: String {
        switch self {
        case .requested: "exclamationmark.circle"
        case .in_progress: "scissors"
        case .completed: "checkmark.circle.fill"
        case .cancelled: "xmark.circle"
        }
    }
}

struct Alteration: Identifiable, Codable, Hashable {
    let id: UUID
    var boutiqueId: UUID
    var orderId: UUID
    var appointmentId: UUID?
    var roundNumber: Int
    var status: AlterationStatus
    var requestNotes: String
    var internalNotes: String?
    var targetDate: String?
    var completedAt: Date?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status
        case boutiqueId = "boutique_id"
        case orderId = "order_id"
        case appointmentId = "appointment_id"
        case roundNumber = "round_number"
        case requestNotes = "request_notes"
        case internalNotes = "internal_notes"
        case targetDate = "target_date"
        case completedAt = "completed_at"
        case createdAt = "created_at"
    }
}

struct NewAlteration: Encodable {
    let boutique_id: UUID
    let order_id: UUID
    let round_number: Int
    let request_notes: String
    let internal_notes: String?
    let target_date: String?
}
