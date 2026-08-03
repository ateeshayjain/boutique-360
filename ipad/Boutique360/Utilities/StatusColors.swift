import SwiftUI

/// One home for status → colour.
///
/// This mapping was duplicated across four views (`OrdersListView` twice,
/// `OrderDetailView`, `CustomerDetailView`) plus a dead `tint: String` on the
/// enum itself that nothing read. Five copies of one decision is five places
/// to forget when a case is added — and adding `.unknown` proved it: every
/// copy had to be edited by hand.
///
/// Lives in the UI layer on purpose. No file in `Models/` imports SwiftUI, and
/// that separation is worth more than the convenience of putting `Color` on
/// the enum.
extension OrderStatus {
    var color: Color {
        switch self {
        case .pending:   .orange
        case .confirmed: .blue
        case .packed:    .indigo
        case .shipped:   .purple
        case .delivered: .green
        case .cancelled: .gray
        case .returned:  .red
        // A status this build doesn't recognise reads as neutral, never as a
        // state the owner might act on. See `DecodableWithFallback`.
        case .unknown:   .gray
        }
    }
}
