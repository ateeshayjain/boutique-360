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
    /// Which input fetches failed — the honest-degradation channel. The view
    /// blanks exactly the tiles/lanes whose dependency failed; empty-but-
    /// loaded inputs render as real zeros.
    enum Input: Hashable { case orders, jobCards, events, alterations, designs, payments, appointments }

    struct Board: Equatable {
        let needsYou: [Item]
        let moneyDue: MoneyDue
        let atRiskCount: Int            // ONLY overdue/late/atRisk members —
                                        // NOT needsYou.count (needsYou also
                                        // holds ready-to-deliver rows)
        let pipeline: Pipeline
        let todayFittings: Int
        let todayDeliveries: Int        // orders in packed/shipped (hand-over pipeline)
        let failed: Set<Input>          // passthrough of build's failures param
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
                      calendar: Calendar = .current) -> Board
}
```

**Degradation map (view renders "—" for):** Money tile when `payments` ∈
failed · At-risk tile + needsYou list hidden when `orders` or `jobCards` ∈
failed · trial/alter lane when `alterations` ∈ failed · designing lane when
`designs` ∈ failed · Today tile's fittings when `appointments` ∈ failed ·
`events` failure is banner-only (a missed done-signal degrades verdicts
pessimistically — the honest direction). Additionally, when `payments` ∈
failed the aggregator emits `.deliver` (never `.deliverAndCollect`) for
ready rows — an empty receivedByOrder would otherwise show the full order
total as "due", a subtly fake number. Any non-empty `failed` also keeps the
existing stale-data banner visible (Unit 4 sets `loadFailed`).

Rules (all pure, all tested):

- **Done-signal (single definition, reused everywhere below):** an order's
  production is done iff its job card status ∈ {ready, delivered} OR its
  latest karigar event is `.ready` — identical to the R1 resolver in
  `SlackBadge.swift`.
- **needsYou membership — ready check runs FIRST:**
  1. *Ready-to-deliver:* done-signal true AND order status ∉ {delivered,
     cancelled, returned}. These orders join needsYou with a delivery action
     and are EXCLUDED from the risk groups entirely (finished work can't be
     "overdue" — the sort and atRiskCount never see them).
  2. *Risk:* remaining orders whose verdict ∈ {overdue, late, atRisk} via
     `OrderSlack.verdict(for:jobCard:latestEvent:today:)`.
- **Severity sort:** overdue (days desc) → late (days desc) → atRisk (slack
  asc) → ready-to-deliver (balance desc). An overdue-but-ready order is in
  the ready group by rule 1 above. Stable within groups by event date
  ascending (nil last), then order number — deterministic for tests.
- **Action derivation:** ready-to-deliver + balance>0 →
  `.deliverAndCollect(balance)`; ready-to-deliver + paid → `.deliver`;
  overdue/late → `.chaseKarigar`; atRisk → `.decideToday`.
- **moneyDue:** over orders not in {cancelled, returned} where
  `Money.roundedToPaise(total − received) > 0` (sub-paise FP drift never
  shows a phantom balance). `oldestDays` from `placedAt ?? createdAt` of the
  oldest such order; 0 when none.
- **pipeline — order-centric, each order in AT MOST one lane, evaluated in
  this order:**
  1. `ready`: done-signal true OR order status ∈ {packed, shipped} (order
     not delivered/cancelled/returned). Counted once per order — no
     card-vs-order double count.
  2. `withKarigar`: job card status ∈ {issued, in_progress}.
  3. `toStart`: order status ∈ {pending, confirmed} AND (no job card OR job
     card status == draft) — a draft card means production hasn't started,
     so the order stays visible in toStart rather than vanishing.
  (Design-only job cards — `order_id` nil — are invisible to the order
  lanes by construction; intended, since without an order there is no
  commitment to track.) `trialAlter` counts open alterations
  (requested/in_progress) and
  `designing` arrives pre-counted (the view passes
  `designs.filter { [.draft, .rendered, .shared_with_customer].contains($0.status) }.count`)
  — these two lanes count their own entity type, disjoint from the order
  lanes by construction.
- **todayFittings** = `todaysAppointments` passthrough (view already computes
  it). **todayDeliveries** = count of orders with status ∈ {packed, shipped}
  — the hand-over pipeline (no job-card condition; packed/shipped IS the
  delivery signal).
- **customerName fallback:** `customersById` miss → "—" (fetch failure or FK
  gap must not crash a row).
- Empty inputs → empty board, zeroed tiles. Never throws.

### Unit 2 — `Services/AlterationsService.listOpen(boutiqueId:)`

One new method: `select * where boutique_id = ? and status in
('requested','in_progress') order by created_at` — boutique-scoped per
CLAUDE.md, single query, deterministic order.

### Unit 3 — `Features/Dashboard/MorningBoardView.swift`

Stateless renderer of `MorningBoard.Board` (Item already carries
customerName — no separate customers parameter):
- **Tile row:** Today (fittings + deliveries) · Money due (INR total, count,
  "oldest Nd") · At risk (red tint when count > 0, green "All on track" when
  0 and `orders`/`jobCards` not in `failed`).
- **Needs-you list:** up to 6 rows (full count shown in the tile); each row =
  `SlackBadge` (NON-compact mode, so ready rows with `noEvent`/`noPlan`
  verdicts still show their gray/hollow badge) + customer name +
  garment/order# + action label; row is a `NavigationLink(value: order)` —
  DashboardView gains `.navigationDestination(for: Order.self)` (same
  pattern as OrdersListView). `.deliverAndCollect` shows the amount.
- **Pipeline strip:** 5 proportional-width lane blocks (min width for
  zero-count lanes), count + label, display-only.
- Degraded states: per the Unit 1 degradation map — "—" only for tiles/lanes
  whose input is in `Board.failed`; genuinely-empty inputs render real
  zeros; any failure keeps the stale banner visible.

### Unit 4 — DashboardView integration

- `load()` gains best-effort parallel fetches: job cards
  (`JobCardsService.forOrders(orders, bid)`), latest events
  (`JobCardEventsService.forJobCards(cards, bid)`), open alterations
  (`AlterationsService.listOpen(boutiqueId:)`), designs
  (`DesignsService.list()` → designing count). Each wrapped in the existing
  `(result, failed)` pattern; failures set `loadFailed` (stale banner) and
  leave that input empty.
- Payment sums: reuse `PaymentsService.capturedSumsForOrders` — called ONCE
  with the union candidate set (all orders not cancelled/returned) and shared
  by both the moneyDue computation and the existing overdue section. The
  overdue section KEEPS its own downstream filters (excludes pending, ≥7-day
  age) applied to the shared result — its behavior must not change; only the
  fetch is consolidated.
- `MorningBoardView(board:)` renders between `headerSection` and
  `todaysRevenueCard`.

### Testing (`MorningBoardTests`, pure)

- Severity ordering: mixed verdicts sort overdue→late→atRisk→ready;
  deterministic tie-break (event date, then order number).
- Ready-beats-overdue: an overdue-but-ready order lands in the ready group
  with a delivery action and is excluded from atRiskCount.
- atRiskCount counts only overdue/late/atRisk (needsYou may be longer).
- moneyDue: excludes cancelled/returned; sums partial payments; oldestDays
  math; zero state; sub-paise drift not counted (roundedToPaise guard).
- Pipeline lane exclusivity: order without card → toStart; draft card →
  still toStart; issued card → withKarigar (not both); packed order with
  ready card → ready once (no double count); ready event moves an
  in_progress card's order to ready; alterations counted from open statuses
  only.
- todayDeliveries counts packed/shipped only.
- Degradation: failures set passes through to Board.failed; empty-but-loaded
  inputs produce zeros with empty failed set.
- Empty inputs → zeroed board.
- needsYou includes ready-to-deliver even when slack comfortable; customer
  lookup miss renders "—".

### Error handling

Aggregator is total (never throws). View-level failures ride the existing
stale-banner mechanism. Secondary-fetch failure must never clobber the
primary orders list (same rule as R1's list badges).
