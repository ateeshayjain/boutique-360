# Design: Exception-first morning board (R2)

**Date:** 2026-07-28 · **Status:** approved by owner (this doc formalizes it)
**Roadmap item:** R2 · **Depends on:** R1 `OrderSlack` (shipped), R4d karigar
events (shipped).
**Context docs:** `docs/app-map.md` §7 · morning-board design discussion
(three tiles + slack-sorted needs-you list + pipeline strip mockup).

## Problem

The Dashboard answers "what happened" (revenue, counts) but not the owner's
real morning question: **"what goes wrong if I don't touch it today?"**
Slack verdicts now exist per order (R1) but nothing aggregates them.

## Goals

- A board at the top of the existing Dashboard: 3 tiles (Today · Money due ·
  At risk), a needs-you list sorted worst-first by slack, and a 5-lane
  pipeline strip.
- Pure, tested aggregation; zero schema changes; best-effort fetches that
  degrade honestly (never fake zeros).

## Non-goals (YAGNI)

- Lane tap-through to other sidebar sections (needs shell navigation surgery;
  deferred — lanes are display-only in v1).
- Removing/reworking any existing Dashboard section (they move below, intact).
- Payment-link "sent but unopened" state (needs Razorpay webhook plumbing; R4a
  territory).
- Push notifications for at-risk orders.

## Design

### Unit 1 — `Utilities/MorningBoard.swift` (pure aggregator, tested)

```swift
enum MorningBoard {
    struct Item: Equatable, Identifiable {
        let id: UUID                    // order id
        let orderNumber: String
        let customerName: String
        let garmentHint: String?        // job card garment_type, else nil
        let verdict: OrderSlack.Verdict
        let action: Action
        let balanceDue: Double          // 0 when fully paid
    }
    enum Action: Equatable {
        case chaseKarigar               // overdue / late
        case decideToday                // atRisk
        case deliverAndCollect(Double)  // ready card + balance > 0
        case deliver                    // ready card, fully paid
    }
    struct MoneyDue: Equatable {
        let total: Double               // Σ (order.total − received)
        let orderCount: Int
        let oldestDays: Int             // age of oldest order with balance
    }
    struct Pipeline: Equatable {
        let designing: Int              // designs in draft/rendered/shared_with_customer
        let toStart: Int                // pending/confirmed orders WITHOUT a job card
        let withKarigar: Int            // job cards issued/in_progress
        let trialAlter: Int             // alterations requested/in_progress
        let ready: Int                  // job cards ready + orders packed/shipped
    }
    struct Board: Equatable {
        let needsYou: [Item]
        let moneyDue: MoneyDue
        let atRiskCount: Int            // == needsYou.count
        let pipeline: Pipeline
        let todayFittings: Int
        let todayDeliveries: Int        // hand-over candidates — see rule below
    }

    static func build(orders: [Order],
                      jobCardsByOrder: [UUID: JobCard],
                      latestEventByCard: [UUID: JobCardEvent],
                      openAlterations: [Alteration],
                      designingCount: Int,
                      todaysAppointments: Int,
                      customersById: [UUID: Customer],
                      receivedByOrder: [UUID: Double],
                      today: Date = Date(),
                      calendar: Calendar = .current) -> Board
}
```

Rules (all pure, all tested):

- **needsYou membership:** verdict ∈ {overdue, late, atRisk} via
  `OrderSlack.verdict(for:jobCard:latestEvent:today:)`, PLUS ready-to-deliver
  orders (job card status ready OR latest event `.ready`, order not yet
  delivered/cancelled/returned) regardless of slack — delivering is today's
  action even when comfortable.
- **Severity sort:** overdue (days desc) → late (days desc) → atRisk (slack
  asc) → ready-to-deliver (balance desc). Stable within groups by event date
  ascending, then order number for determinism.
- **Action derivation:** overdue/late → `.chaseKarigar`; atRisk →
  `.decideToday`; ready + balance>0 → `.deliverAndCollect(balance)`; ready +
  paid → `.deliver`. A ready order that is ALSO overdue keeps the delivery
  action (it's finished — chase no longer applies) — ready check runs first.
- **moneyDue:** over orders not in {cancelled, returned} with
  `total − received > 0` (paise-compared via `Money.equalAtPaise` guard).
  `oldestDays` from `placedAt ?? createdAt` of the oldest such order; 0 when
  none.
- **pipeline:** counts per the lane definitions above. An order counts in
  `toStart` only if pending/confirmed AND `jobCardsByOrder[id] == nil`.
  A job card counts in exactly one lane by its status (issued/in_progress →
  withKarigar; ready → ready). `designing` arrives pre-counted (the view
  passes `designs.filter{...}.count`) to keep Design out of the aggregator's
  dependency set.
- **todayFittings** = `todaysAppointments` passthrough (view already computes
  it). **todayDeliveries** = orders in packed/shipped whose job card is
  done/ready — the "hand over today" candidates.
- Empty inputs → empty board, zeroed tiles. Never throws.

### Unit 2 — `Services/AlterationsService.listOpen(boutiqueId:)`

One new method: `select * where boutique_id = ? and status in
('requested','in_progress')` — boutique-scoped per CLAUDE.md, single query.

### Unit 3 — `Features/Dashboard/MorningBoardView.swift`

Stateless renderer of `MorningBoard.Board`:
- **Tile row:** Today (fittings + deliveries) · Money due (INR total, count,
  "oldest Nd") · At risk (red tint when count > 0, green "all clear" when 0
  and data loaded).
- **Needs-you list:** up to 6 rows (full count shown in the tile); each row =
  `SlackBadge` + customer name + garment/order# + action label; row is a
  `NavigationLink(value: order)` — DashboardView gains
  `.navigationDestination(for: Order.self)` (same pattern as OrdersListView).
  Rows with `.deliverAndCollect` show the amount in the action label.
- **Pipeline strip:** 5 proportional-width lane blocks (min width for
  zero-count lanes), count + label, display-only.
- Empty/degraded states: when the board inputs failed to load, tiles show "—"
  and the existing stale-data banner explains why (no fake zeros); when
  genuinely empty, At-risk tile shows a green "All on track".

### Unit 4 — DashboardView integration

- `load()` gains best-effort parallel fetches: job cards
  (`JobCardsService.forOrders(orders, bid)`), latest events
  (`JobCardEventsService.forJobCards(cards, bid)`), open alterations
  (`AlterationsService.listOpen(boutiqueId:)`), designs
  (`DesignsService.list()` → designing count). Each wrapped in the existing
  `(result, failed)` pattern; failures set `loadFailed` (stale banner) and
  leave that input empty.
- Payment sums: reuse `PaymentsService.capturedSumsForOrders` — called ONCE
  for all non-cancelled orders and shared by both the moneyDue computation
  and the existing overdue section (replacing that section's separate call —
  net query count unchanged).
- `MorningBoardView(board:customers:)` renders between `headerSection` and
  `todaysRevenueCard`.

### Testing (`MorningBoardTests`, pure)

- Severity ordering: mixed verdicts sort overdue→late→atRisk→ready.
- Ready-beats-overdue action rule.
- moneyDue: excludes cancelled/returned; sums partial payments; oldestDays
  math; zero state.
- Pipeline: order without card → toStart; same order with issued card →
  withKarigar (not both); ready event moves card's order out of needs-chase
  into deliver; alterations counted from open statuses only.
- Empty inputs → zeroed board.
- needsYou includes ready-to-deliver even when slack comfortable.

### Error handling

Aggregator is total (never throws). View-level failures ride the existing
stale-banner mechanism. Secondary-fetch failure must never clobber the
primary orders list (same rule as R1's list badges).
