import Foundation

/// R2 — pure aggregator behind the Dashboard's exception-first morning board.
/// All rules are specified in
/// docs/superpowers/specs/2026-07-28-morning-board-design.md — the spec is
/// normative; this file implements it without invention.
enum MorningBoard {
    /// Which input fetches failed — the honest-degradation channel. The view
    /// blanks exactly the tiles/lanes whose dependency failed; empty-but-
    /// loaded inputs render as real zeros.
    enum Input: Hashable {
        case orders, jobCards, events, alterations, designs, payments, appointments
    }

    enum Action: Equatable {
        case chaseKarigar                // overdue / late
        case decideToday                 // atRisk
        case deliverAndCollect(Double)   // ready + balance > 0
        case deliver                     // ready, paid (or payments unknown)
    }

    struct Item: Equatable, Identifiable {
        let id: UUID                     // order id
        let orderNumber: String
        let customerName: String
        let garmentHint: String?
        let verdict: OrderSlack.Verdict
        let action: Action
        let balanceDue: Double
    }

    struct MoneyDue: Equatable {
        let total: Double
        let orderCount: Int
        let oldestDays: Int
        init(total: Double, orderCount: Int, oldestDays: Int) {
            self.total = total; self.orderCount = orderCount; self.oldestDays = oldestDays
        }
    }

    struct Pipeline: Equatable {
        let designing: Int
        let toStart: Int
        let withKarigar: Int
        let trialAlter: Int
        let ready: Int
        init(designing: Int, toStart: Int, withKarigar: Int, trialAlter: Int, ready: Int) {
            self.designing = designing; self.toStart = toStart
            self.withKarigar = withKarigar; self.trialAlter = trialAlter; self.ready = ready
        }
    }

    struct Board: Equatable {
        let needsYou: [Item]
        let moneyDue: MoneyDue
        let atRiskCount: Int             // overdue/late/atRisk only — NOT needsYou.count
        let pipeline: Pipeline
        let todayFittings: Int
        let todayDeliveries: Int         // orders in packed/shipped
        let failed: Set<Input>
    }

    static func build(orders: [Order],
                      jobCardsByOrder: [UUID: JobCard],
                      latestEventByCard: [UUID: JobCardEvent],
                      openAlterations: [Alteration],
                      designingCount: Int,
                      todaysAppointments: Int,
                      customersById: [UUID: Customer],
                      receivedByOrder: [UUID: Double],
                      failures: Set<Input>,
                      today: Date = Date(),
                      calendar: Calendar = .current) -> Board {

        func card(_ o: Order) -> JobCard? { jobCardsByOrder[o.id] }
        func latestEvent(_ o: Order) -> JobCardEvent? {
            card(o).flatMap { latestEventByCard[$0.id] }
        }
        // Single done-signal definition — identical to the R1 resolver.
        func done(_ o: Order) -> Bool {
            guard let c = card(o) else { return false }
            return c.status == .ready || c.status == .delivered
                || latestEvent(o)?.event == .ready
        }
        func name(_ o: Order) -> String { customersById[o.customerId]?.name ?? "—" }
        func balance(_ o: Order) -> Double {
            Money.roundedToPaise(o.total - (receivedByOrder[o.id] ?? 0))
        }
        let terminal: Set<OrderStatus> = [.delivered, .cancelled, .returned]

        // ── needsYou: ready check FIRST, then risk on the remainder.
        struct Ranked {
            let item: Item
            let rank: Int          // overdue 0 · late 1 · atRisk 2 · ready 3
            let primary: Double    // sort key within group (see below)
            let eventDate: String? // tie-break 1 (asc, nil last)
        }
        var ranked: [Ranked] = []
        var atRisk = 0

        for o in orders where !terminal.contains(o.status) {
            let verdict = OrderSlack.verdict(for: o, jobCard: card(o),
                                             latestEvent: latestEvent(o), today: today)
            if done(o) {
                // Ready-to-deliver: excluded from risk groups entirely.
                let bal = balance(o)
                let action: Action = (failures.contains(.payments) || bal <= 0)
                    ? .deliver : .deliverAndCollect(bal)
                ranked.append(Ranked(
                    item: Item(id: o.id, orderNumber: o.orderNumber,
                               customerName: name(o), garmentHint: card(o)?.garmentType,
                               verdict: verdict, action: action, balanceDue: max(bal, 0)),
                    rank: 3,
                    primary: -max(bal, 0),          // balance desc
                    eventDate: o.eventDate))
                continue
            }
            let rank: Int
            let primary: Double
            let action: Action
            switch verdict {
            case .overdue(let d): rank = 0; primary = Double(-d); action = .chaseKarigar
            case .late(let d):    rank = 1; primary = Double(-d); action = .chaseKarigar
            case .atRisk(let s):  rank = 2; primary = Double(s);  action = .decideToday
            default: continue
            }
            atRisk += 1
            ranked.append(Ranked(
                item: Item(id: o.id, orderNumber: o.orderNumber,
                           customerName: name(o), garmentHint: card(o)?.garmentType,
                           verdict: verdict, action: action, balanceDue: max(balance(o), 0)),
                rank: rank, primary: primary, eventDate: o.eventDate))
        }

        let needsYou = ranked.sorted { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            if a.primary != b.primary { return a.primary < b.primary }
            switch (a.eventDate, b.eventDate) {              // asc, nil last
            case let (x?, y?) where x != y: return x < y
            case (nil, .some): return false
            case (.some, nil): return true
            default: return a.item.orderNumber < b.item.orderNumber
            }
        }.map(\.item)

        // ── moneyDue
        var dueTotal = 0.0
        var dueCount = 0
        var oldest: Date?
        for o in orders where o.status != .cancelled && o.status != .returned {
            let bal = balance(o)
            guard bal > 0 else { continue }
            dueTotal += bal
            dueCount += 1
            let anchor = o.placedAt ?? o.createdAt
            if oldest == nil || anchor < oldest! { oldest = anchor }
        }
        let oldestDays = oldest.map {
            calendar.dateComponents([.day],
                                    from: calendar.startOfDay(for: $0),
                                    to: calendar.startOfDay(for: today)).day ?? 0
        } ?? 0

        // ── pipeline: order-centric, at most one lane, precedence
        //    ready → withKarigar → toStart.
        var toStart = 0, withKarigar = 0, ready = 0
        for o in orders where !terminal.contains(o.status) {
            if done(o) || o.status == .packed || o.status == .shipped {
                ready += 1
            } else if let c = card(o), c.status == .issued || c.status == .in_progress {
                withKarigar += 1
            } else if o.status == .pending || o.status == .confirmed,
                      card(o) == nil || card(o)?.status == .draft {
                toStart += 1
            }
        }
        let trialAlter = openAlterations
            .filter { $0.status == .requested || $0.status == .in_progress }
            .count

        let todayDeliveries = orders
            .filter { $0.status == .packed || $0.status == .shipped }
            .count

        return Board(
            needsYou: needsYou,
            moneyDue: MoneyDue(total: dueTotal, orderCount: dueCount, oldestDays: oldestDays),
            atRiskCount: atRisk,
            pipeline: Pipeline(designing: designingCount, toStart: toStart,
                               withKarigar: withKarigar, trialAlter: trialAlter, ready: ready),
            todayFittings: todaysAppointments,
            todayDeliveries: todayDeliveries,
            failed: failures
        )
    }
}
