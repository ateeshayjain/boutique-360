import SwiftUI

/// Chronological view of all events related to an order. Reads append-only
/// `events` table, plus (R4d) karigar progress events from the order's job
/// card — merged newest-context-last so the owner reconstructs "what
/// happened with this order, when" in one place.
struct OrderTimelineView: View {
    let orderId: UUID

    @EnvironmentObject private var ctx: BoutiqueContext
    @State private var events: [AppEvent] = []
    @State private var karigarEvents: [JobCardEvent] = []

    var body: some View {
        Section("Timeline") {
            if events.isEmpty && karigarEvents.isEmpty {
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
                // R4d: karigar updates, visually distinct from app events.
                ForEach(karigarEvents) { k in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: karigarIcon(k.event))
                            .foregroundStyle(k.event == .ready ? .green : .secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Karigar: \(karigarLabel(k.event))").font(.subheadline)
                            Text(k.createdAt.formatted(.dateTime.day().month().hour().minute()))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .task {
            events = (try? await EventsService.listForOrder(orderId)) ?? []
            if let bid = ctx.boutiqueId,
               let card = (try? await JobCardsService.forOrders([orderId], boutiqueId: bid))?.first {
                karigarEvents = (try? await JobCardEventsService.list(jobCardId: card.id, boutiqueId: bid)) ?? []
            }
        }
    }

    private func icon(for name: String) -> String {
        if name.contains("status_changed") { return "arrow.right.circle" }
        if name.contains("appointment") { return "calendar" }
        if name.contains("payment") { return "indianrupeesign.circle" }
        return "circle.fill"
    }

    private func karigarIcon(_ kind: JobCardEvent.Kind) -> String {
        switch kind {
        case .started:       "figure.walk"
        case .stitchingDone: "scissors"
        case .ready:         "checkmark.seal.fill"
        }
    }
    private func karigarLabel(_ kind: JobCardEvent.Kind) -> String {
        switch kind {
        case .started:       "Shuru kiya (started)"
        case .stitchingDone: "Silai poori (stitching done)"
        case .ready:         "Taiyaar hai (ready)"
        }
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
