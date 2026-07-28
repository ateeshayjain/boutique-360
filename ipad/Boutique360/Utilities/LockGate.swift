import Foundation

/// R3 — pure lock-validation. The LockSheet's Lock button is enabled iff
/// `blockers(...)` returns empty; each Blocker carries what the UI needs to
/// explain itself. Check order is fixed: advance → event → breakup.
/// Spec: docs/superpowers/specs/2026-07-28-lock-screen-design.md Unit 3.
enum LockGate {
    enum Blocker: Equatable {
        case noAdvance                              // no captured payment
        case eventInsideBuffer(mustFinishBy: Date)  // must-finish-by past, rush not accepted
        case breakupMismatch(sum: Double, subtotal: Double)
    }

    /// Empty array = lockable. Pure; never throws.
    static func blockers(advancePaid: Double,
                         eventDate: Date?, fulfillment: FulfillmentMethod?,
                         alterationBufferDays: Int, rushAccepted: Bool,
                         breakup: (fabric: Double, work: Double, other: Double)?,
                         subtotal: Double,
                         today: Date, calendar: Calendar = .current) -> [Blocker] {
        var result: [Blocker] = []

        if advancePaid <= 0 {
            result.append(.noAdvance)
        }

        if let mf = OrderSlack.mustFinishBy(eventDate: eventDate,
                                            fulfillment: fulfillment,
                                            alterationBufferDays: alterationBufferDays,
                                            calendar: calendar),
           mf < calendar.startOfDay(for: today),
           !rushAccepted {
            result.append(.eventInsideBuffer(mustFinishBy: mf))
        }

        if let b = breakup {
            let sum = b.fabric + b.work + b.other
            if !Money.equalAtPaise(sum, subtotal) {
                result.append(.breakupMismatch(sum: sum, subtotal: subtotal))
            }
        }

        return result
    }
}
