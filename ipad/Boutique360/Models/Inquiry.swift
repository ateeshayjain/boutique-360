import Foundation

enum InquiryStatus: String, Codable, CaseIterable, Identifiable {
    case new, consulting, measurements, quoted, confirmed
    case in_production, ready, delivered, lost

    var id: String { rawValue }
    var label: String {
        switch self {
        case .new: "New"
        case .consulting: "Consulting"
        case .measurements: "Measurements"
        case .quoted: "Quoted"
        case .confirmed: "Confirmed"
        case .in_production: "In Production"
        case .ready: "Ready"
        case .delivered: "Delivered"
        case .lost: "Lost"
        }
    }
    /// Kanban column order
    static var kanbanColumns: [InquiryStatus] {
        [.new, .consulting, .measurements, .quoted, .confirmed, .in_production, .ready, .delivered]
    }
}

struct Inquiry: Identifiable, Codable, Hashable {
    let id: UUID
    var boutiqueId: UUID
    var inquiryNumber: String
    var customerId: UUID
    var status: InquiryStatus
    var occasion: String?
    var eventDate: String?     // YYYY-MM-DD
    var budgetRange: String?
    var notes: String?
    var source: String?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status, occasion, notes, source
        case boutiqueId = "boutique_id"
        case inquiryNumber = "inquiry_number"
        case customerId = "customer_id"
        case eventDate = "event_date"
        case budgetRange = "budget_range"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct NewInquiry: Encodable {
    let boutique_id: UUID
    let inquiry_number: String
    let customer_id: UUID
    let occasion: String?
    let event_date: String?
    let budget_range: String?
    let notes: String?
    let source: String
}
