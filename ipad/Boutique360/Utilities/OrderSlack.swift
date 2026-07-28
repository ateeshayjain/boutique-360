import Foundation

/// R1 — honest per-order deadline slack. Pure; all inputs injected.
/// Verdict precedence and formula are specified in
/// docs/superpowers/specs/2026-07-28-slack-engine-karigar-link-design.md:
/// cancelled/returned → noEvent · event nil → noEvent · due nil → noPlan ·
/// overdue guard → overdue · else classify by
/// slack = daysToEvent − workRemaining − alterationBuffer − deliveryDays.
enum OrderSlack {
    static let shipDeliveryDays = 3
    static let minimumProductionDays = 7

    enum Verdict: Equatable {
        case noEvent                    // no event date — slack undefined, never at-risk
        case noPlan                     // event set, no job-card due date — can't compute
        case overdue(daysOverdue: Int)  // job card past due and NOT done — always red
        case late(days: Int)            // slack < 0
        case atRisk(days: Int)          // 0 ≤ slack ≤ 1
        case comfortable(days: Int)     // slack ≥ 2
    }

    static func evaluate(eventDate: Date?, jobCardDue: Date?, jobCardDone: Bool,
                         orderStatus: OrderStatus, fulfillment: FulfillmentMethod?,
                         alterationBufferDays: Int, today: Date,
                         calendar: Calendar = .current) -> Verdict {
        if orderStatus == .cancelled || orderStatus == .returned { return .noEvent }
        guard let event = eventDate else { return .noEvent }
        guard let due = jobCardDue else { return .noPlan }

        // Day-granularity math: startOfDay everywhere so time-of-day never
        // shifts a verdict across midnight boundaries.
        let d0 = calendar.startOfDay(for: today)
        let dEvent = calendar.startOfDay(for: event)
        let dDue = calendar.startOfDay(for: due)
        let delivered = orderStatus == .delivered
        let done = jobCardDone || delivered

        // Honesty guard: an unfinished job past its due date must never show
        // green — remaining work is unknown-but-positive. Delivery supersedes
        // (a delivered order with a never-closed card is not overdue).
        if !done, dDue < d0 {
            let over = calendar.dateComponents([.day], from: dDue, to: d0).day ?? 0
            return .overdue(daysOverdue: over)
        }

        let daysToEvent = calendar.dateComponents([.day], from: d0, to: dEvent).day ?? 0
        let workRemaining = done ? 0 : max(0, calendar.dateComponents([.day], from: d0, to: dDue).day ?? 0)
        let deliveryDays = (fulfillment == .ship) ? shipDeliveryDays : 0
        let slack = daysToEvent - workRemaining - alterationBufferDays - deliveryDays

        if slack < 0 { return .late(days: -slack) }
        if slack <= 1 { return .atRisk(days: slack) }
        return .comfortable(days: slack)
    }

    /// event − buffer − delivery: the date production must finish by for the
    /// event to be safe. Nil when there is no event date. Used by
    /// OrderCreateView before any job card exists (creation-time semantics).
    static func mustFinishBy(eventDate: Date?, fulfillment: FulfillmentMethod?,
                             alterationBufferDays: Int,
                             calendar: Calendar = .current) -> Date? {
        guard let event = eventDate else { return nil }
        let deliveryDays = (fulfillment == .ship) ? shipDeliveryDays : 0
        return calendar.date(byAdding: .day, value: -(alterationBufferDays + deliveryDays),
                             to: calendar.startOfDay(for: event))
    }
}
