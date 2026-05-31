import SwiftUI

/// M8 fix: the SwiftUI Color mapping for timeline events lives here, NOT on
/// the model. Keeps Models/ free of UI dependencies so they're consumable by
/// tests, server-side code, or widget extensions.
extension CustomerTimelineEvent.Kind {
    var tint: Color {
        switch self {
        case .customerJoined:          .gray
        case .inquiryCreated, .inquiryStatusChanged: .indigo
        case .measurementTaken:        .purple
        case .designCreated, .designSketchSaved, .designRendered, .designTryOn: .pink
        case .orderPlaced, .orderStatusChanged: .blue
        case .paymentCaptured:         .green
        case .jobCardIssued:           .orange
        case .alterationRequested:     .yellow
        case .alterationCompleted:     .mint
        case .appointmentScheduled, .appointmentCompleted: .teal
        }
    }
}
