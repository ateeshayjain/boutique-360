import Foundation

/// R4a — pure draft builder for the Dashboard's Reminders section.
///
/// The inclusion rules, `forDate` semantics, degraded-input suppression and
/// sort order are specified in
/// docs/superpowers/specs/2026-07-28-reminders-roles-design.md Unit 2 and are
/// normative — transcribed here, not re-derived.
///
/// Two rules carry real consequences and are worth reading before editing:
/// 1. **No un-gated draft may contain a rupee amount.** Only payment drafts
///    are hidden in assistant mode, so fitting/ready copy must stay
///    money-free — which is why the ready message drops the `Total:` clause
///    that `CustomerNotifier.orderReadyPlan` carries.
/// 2. **A failed input suppresses the draft kinds it feeds.** An empty
///    `receivedByOrder` would make every balance look like the full order
///    total, i.e. nudge customers for money they already paid.
enum ReminderDrafts {
    /// `fitting` matches `AppointmentType.fitting` — the app's own term.
    /// There is no "trial" anywhere in the data model.
    enum Kind: String, Equatable, CaseIterable { case fitting, payment, ready }

    struct Draft: Equatable, Identifiable {
        let kind: Kind
        let subjectId: UUID
        let forDate: String          // YYYY-MM-DD; semantics differ per kind
        let customerId: UUID
        let customerName: String
        let whatsappTarget: String   // non-optional: no target ⇒ no draft
        let message: String
        let orderNumber: String?
        let amountDue: Double?       // payment kind ONLY (see rule 1 above)

        var id: String { ReminderDrafts.key(kind: kind, subjectId: subjectId, forDate: forDate) }
    }

    /// THE single key format. Both this file and `RemindersService` must call
    /// it — never interpolate by hand. Swift's `uuidString` is uppercase and
    /// Postgres returns lowercase, so normalising here is what keeps dedup
    /// working across the two sides.
    static func key(kind: Kind, subjectId: UUID, forDate: String) -> String {
        "\(kind.rawValue)-\(subjectId.uuidString.lowercased())-\(forDate)"
    }

    /// `logged` is non-optional by design: the caller MUST NOT call this when
    /// the reminder-log fetch failed. Passing an empty set would read as
    /// "nothing handled yet" and re-surface every draft the owner already sent.
    static func build(appointments: [Appointment],
                      orders: [Order],
                      jobCardsByOrder: [UUID: JobCard],
                      latestEventByCard: [UUID: JobCardEvent],
                      receivedByOrder: [UUID: Double],
                      customersById: [UUID: Customer],
                      logged: Set<String>,
                      failedInputs: Set<MorningBoard.Input>,
                      boutiqueName: String,
                      today: Date,
                      calendar: Calendar = .current) -> [Draft] {

        // ── Degraded-input suppression, applied BEFORE every other rule.
        let allowFitting = !failedInputs.contains(.appointments)
        let allowPayment = !failedInputs.contains(.orders) && !failedInputs.contains(.payments)
        let allowReady = !failedInputs.contains(.orders)
            && !failedInputs.contains(.jobCards)
            && !failedInputs.contains(.events)

        let startOfToday = calendar.startOfDay(for: today)
        let terminal: Set<OrderStatus> = [.delivered, .cancelled, .returned]

        /// Consent gate (DPDP): no consent or no reachable number ⇒ no draft
        /// at all — not a disabled row. We don't surface prompts to message
        /// people who declined or can't be reached.
        func reachable(_ customerId: UUID) -> (Customer, String)? {
            guard let c = customersById[customerId],
                  c.consentWhatsapp,
                  let target = c.whatsappTarget else { return nil }
            return (c, target)
        }

        func firstName(_ c: Customer) -> String {
            c.name.split(separator: " ").first.map(String.init) ?? c.name
        }

        var drafts: [(sortKey: (Int, Double, String, String), draft: Draft)] = []

        // ── Fitting: appointments today or tomorrow. forDate = the
        //    appointment's date, so one reminder per appointment, ever.
        if allowFitting {
            for appt in appointments where appt.type == .fitting && appt.status == .scheduled {
                let day = calendar.startOfDay(for: appt.scheduledAt)
                let delta = calendar.dateComponents([.day], from: startOfToday, to: day).day ?? -1
                guard delta == 0 || delta == 1 else { continue }
                guard let (customer, target) = reachable(appt.customerId) else { continue }

                let forDate = Formatters.postgresDate.string(from: appt.scheduledAt)
                guard !logged.contains(key(kind: .fitting, subjectId: appt.id, forDate: forDate))
                else { continue }

                let dayText = appt.scheduledAt.formatted(.dateTime.weekday(.wide).day().month())
                let timeText = appt.scheduledAt.formatted(.dateTime.hour().minute())
                let message = "Namaste \(firstName(customer))! Reminder — aapki fitting "
                    + "\(dayText) ko \(timeText) baje hai. — \(boutiqueName)"

                drafts.append((
                    sortKey: (0, appt.scheduledAt.timeIntervalSince1970, customer.name, appt.id.uuidString),
                    draft: Draft(kind: .fitting, subjectId: appt.id, forDate: forDate,
                                 customerId: customer.id, customerName: customer.name,
                                 whatsappTarget: target, message: message,
                                 orderNumber: nil, amountDue: nil)
                ))
            }
        }

        let todayKey = Formatters.postgresDate.string(from: today)

        for order in orders {
            guard !terminal.contains(order.status) || order.status == .delivered else { continue }
            let card = jobCardsByOrder[order.id]
            let latestEvent = card.flatMap { latestEventByCard[$0.id] }
            let done = card.map { $0.status == .ready || $0.status == .delivered } ?? false
                || latestEvent?.event == .ready

            // ── Ready: production finished, order not yet handed over.
            //    Money-free copy by rule 1 — this renders in assistant mode.
            if allowReady, done, !terminal.contains(order.status) {
                if let (customer, target) = reachable(order.customerId),
                   !logged.contains(key(kind: .ready, subjectId: order.id, forDate: todayKey)) {
                    let message = "Hi \(firstName(customer)), your order \(order.orderNumber) "
                        + "from \(boutiqueName) is ready! Drop by or reply for delivery."
                    drafts.append((
                        sortKey: (1, 0, customer.name, order.id.uuidString),
                        draft: Draft(kind: .ready, subjectId: order.id, forDate: todayKey,
                                     customerId: customer.id, customerName: customer.name,
                                     whatsappTarget: target, message: message,
                                     orderNumber: order.orderNumber, amountDue: nil)
                    ))
                }
            }

            // ── Payment: balance outstanding for at least 7 days.
            //    forDate = today, so a dismissed nudge deliberately returns
            //    tomorrow — the balance is still owed.
            guard allowPayment else { continue }
            guard ![OrderStatus.pending, .cancelled, .returned].contains(order.status) else { continue }
            let balance = Money.roundedToPaise(order.total - (receivedByOrder[order.id] ?? 0))
            guard balance > 0 else { continue }
            let anchor = calendar.startOfDay(for: order.placedAt ?? order.createdAt)
            let age = calendar.dateComponents([.day], from: anchor, to: startOfToday).day ?? 0
            guard age >= 7 else { continue }
            guard let (customer, target) = reachable(order.customerId) else { continue }
            guard !logged.contains(key(kind: .payment, subjectId: order.id, forDate: todayKey))
            else { continue }

            let message = "Hi \(firstName(customer)), a gentle reminder — balance of "
                + "\(Formatters.inr(balance)) is pending on order \(order.orderNumber). "
                + "UPI / card / cash all accepted. Thank you! — \(boutiqueName)"
            drafts.append((
                sortKey: (2, -balance, customer.name, order.id.uuidString),
                draft: Draft(kind: .payment, subjectId: order.id, forDate: todayKey,
                             customerId: customer.id, customerName: customer.name,
                             whatsappTarget: target, message: message,
                             orderNumber: order.orderNumber, amountDue: balance)
            ))
        }

        // Group rank → within-group key → customer name → id. Fully
        // deterministic so the list doesn't reshuffle between refreshes.
        return drafts.sorted { a, b in
            if a.sortKey.0 != b.sortKey.0 { return a.sortKey.0 < b.sortKey.0 }
            if a.sortKey.1 != b.sortKey.1 { return a.sortKey.1 < b.sortKey.1 }
            if a.sortKey.2 != b.sortKey.2 { return a.sortKey.2 < b.sortKey.2 }
            return a.sortKey.3 < b.sortKey.3
        }.map(\.draft)
    }
}
