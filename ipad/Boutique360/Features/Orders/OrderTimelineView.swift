import SwiftUI

/// Chronological view of all events related to an order. Reads append-only `events` table.
/// Helps the owner reconstruct "what happened with this order, when".
struct OrderTimelineView: View {
    let orderId: UUID

    @State private var events: [AppEvent] = []

    var body: some View {
        Section("Timeline") {
            if events.isEmpty {
                Text("No events yet — status changes will appear here.")
                    .foregroundStyle(.secondary).font(.caption)
            } else {
                ForEach(events) { e in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(for: e.eventName))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label(for: e)).font(.subheadline)
                            Text(e.occurredAt.formatted(.dateTime.day().month().hour().minute()))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .task { events = (try? await EventsService.listForOrder(orderId)) ?? [] }
    }

    private func icon(for name: String) -> String {
        if name.contains("status_changed") { return "arrow.right.circle" }
        if name.contains("appointment") { return "calendar" }
        if name.contains("payment") { return "indianrupeesign.circle" }
        return "circle.fill"
    }

    private func label(for e: AppEvent) -> String {
        if e.eventName == "order.status_changed",
           let from = e.payloadJson["from"]?.stringValue,
           let to = e.payloadJson["to"]?.stringValue {
            return "Status: \(from.capitalized) → \(to.capitalized)"
        }
        return e.eventName.replacingOccurrences(of: ".", with: " ").capitalized
    }
}
