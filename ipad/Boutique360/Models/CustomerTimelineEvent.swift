import Foundation

/// Unified chronological event on a customer's profile. Aggregated from
/// inquiries, orders, payments, designs, job cards, measurements, alterations,
/// appointments, and the customer record itself.
///
/// Model is UI-free (M8 fix). The SwiftUI `Color` mapping lives in
/// `Features/Customers/CustomerDetailView+Timeline.swift` so this type can be
/// consumed by non-UI code (tests, future widget extensions).
struct CustomerTimelineEvent: Identifiable, Hashable {
    /// M9 fix: composite struct-based ID instead of fragile string concatenation.
    /// Equality is now driven by the type system, not string formatting choices.
    struct ID: Hashable {
        let kind: Kind
        let sourceId: UUID
        let at: Date
    }
    let id: ID
    let title: String
    let subtitle: String?

    var at: Date { id.at }
    var kind: Kind { id.kind }

    enum Kind: String, Hashable {
        case customerJoined
        case inquiryCreated, inquiryStatusChanged
        case measurementTaken
        case designCreated, designSketchSaved, designRendered, designTryOn
        case orderPlaced, orderStatusChanged
        case paymentCaptured
        case jobCardIssued
        case alterationRequested, alterationCompleted
        case appointmentScheduled, appointmentCompleted

        var systemImage: String {
            switch self {
            case .customerJoined:          "person.crop.circle.badge.plus"
            case .inquiryCreated:          "envelope.badge.fill"
            case .inquiryStatusChanged:    "envelope"
            case .measurementTaken:        "ruler"
            case .designCreated:           "scribble.variable"
            case .designSketchSaved:       "pencil.and.scribble"
            case .designRendered:          "sparkles"
            case .designTryOn:             "person.crop.rectangle.badge.plus"
            case .orderPlaced:             "bag.badge.plus"
            case .orderStatusChanged:      "bag"
            case .paymentCaptured:         "indianrupeesign.circle.fill"
            case .jobCardIssued:           "scissors.badge.ellipsis"
            case .alterationRequested:     "exclamationmark.circle"
            case .alterationCompleted:     "checkmark.seal"
            case .appointmentScheduled:    "calendar.badge.plus"
            case .appointmentCompleted:    "calendar.badge.checkmark"
            }
        }
    }
}
