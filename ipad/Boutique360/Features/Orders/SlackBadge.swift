import SwiftUI

/// R1 — colored capsule for an order's slack verdict. Shared by the orders
/// list, order detail, and (later) the R2 morning board. In compact mode,
/// noEvent renders nothing — most orders have no event date and the list
/// shouldn't shout about it.
struct SlackBadge: View {
    let verdict: OrderSlack.Verdict
    var compact: Bool = false

    var body: some View {
        if case .noEvent = verdict, compact {
            EmptyView()
        } else {
            Text(label)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(color.opacity(0.18))
                .foregroundStyle(color)
                .clipShape(Capsule())
                .accessibilityLabel(accessibilityText)
        }
    }

    private var label: String {
        switch verdict {
        case .noEvent:            "no event"
        case .noPlan:             "no plan"
        case .overdue(let d):     "overdue \(d)d"
        case .late(let d):        "late \(d)d"
        case .atRisk(let d):      "\(d)d slack"
        case .comfortable(let d): "\(d)d slack"
        }
    }

    private var color: Color {
        switch verdict {
        case .noEvent:        Color(.systemGray)
        case .noPlan:         Color(.secondaryLabel)
        case .overdue, .late: .red
        case .atRisk:         .orange
        case .comfortable:    .green
        }
    }

    private var accessibilityText: String {
        switch verdict {
        case .noEvent: "No event date"
        case .noPlan: "Event set, production not planned yet"
        case .overdue(let d): "Production overdue by \(d) days"
        case .late(let d): "Late by \(d) days against the event"
        case .atRisk(let d): "At risk, \(d) days slack"
        case .comfortable(let d): "\(d) days slack"
        }
    }
}

extension OrderSlack {
    /// Resolve a verdict from an Order + its (optional) JobCard + the latest
    /// karigar event, using app conventions: postgresDate parsing for the
    /// String "YYYY-MM-DD" columns; done-signal = job card ready/delivered
    /// status, or a karigar `ready` event. (JobCard has no completedAt —
    /// that field lives on StageProgress.)
    static func verdict(for order: Order, jobCard: JobCard?,
                        latestEvent: JobCardEvent? = nil,
                        today: Date = Date()) -> Verdict {
        let event = order.eventDate.flatMap { Formatters.postgresDate.date(from: $0) }
        let due = jobCard?.dueDate.flatMap { Formatters.postgresDate.date(from: $0) }
        let statusDone = jobCard.map { $0.status == .ready || $0.status == .delivered } ?? false
        let done = statusDone || latestEvent?.event == .ready
        return evaluate(eventDate: event, jobCardDue: due, jobCardDone: done,
                        orderStatus: order.status, fulfillment: order.fulfillmentMethod,
                        alterationBufferDays: order.alterationBufferDays, today: today)
    }
}
