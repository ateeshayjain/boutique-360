# Morning Board (R2) Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Exception-first morning board at the top of the Dashboard: 3 tiles, slack-sorted needs-you list, 5-lane pipeline strip.

**Architecture:** Pure `MorningBoard.build` aggregator (tested) consumes data DashboardView already loads plus three new best-effort fetches. `MorningBoardView` is a stateless renderer with an explicit degradation map driven by `Board.failed`. No schema changes.

**Tech Stack:** Swift/SwiftUI iOS 17, XCTest pure-logic-only, existing services (OrderSlack, JobCards/JobCardEvents/Alterations/Payments/Designs).

**Spec:** `docs/superpowers/specs/2026-07-28-morning-board-design.md` — the rules (done-signal, needsYou membership/sort, lane exclusivity, degradation map) are normative; read it first.

**Conventions:** dates via `Formatters.postgresDate`; boutique-scoped queries pass `.eq("boutique_id", …)`; `xcodegen generate` after new files; commit per task with trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Push only at the end to `origin main:boutique-360-ipad-app`.

**Build/test:**
```bash
cd ipad && xcodegen generate && xcodebuild -project Boutique360.xcodeproj -scheme Boutique360 \
  -destination 'platform=iOS Simulator,id=092B3063-9443-4E76-AD24-3918E9A0695C' test -only-testing:Boutique360Tests/MorningBoardTests
```

---

## Chunk 1: Aggregator + service

### Task 1: `AlterationsService.listOpen`

**Files:**
- Modify: `ipad/Boutique360/Services/AlterationsService.swift` (append after `listForOrder`, ~line 12)

- [ ] **Step 1: Add the method:**

```swift
/// R2 — boutique-wide open alterations for the morning board's
/// trial/alter lane. Deterministic order for stable UI.
static func listOpen(boutiqueId: UUID) async throws -> [Alteration] {
    try await SupabaseService.client.from("alterations")
        .select()
        .eq("boutique_id", value: boutiqueId)
        .in("status", values: [AlterationStatus.requested.rawValue,
                               AlterationStatus.in_progress.rawValue])
        .order("created_at", ascending: true)
        .execute()
        .value
}
```

- [ ] **Step 2: Build green. Step 3: Commit** `feat: AlterationsService.listOpen for morning board`

### Task 2: `MorningBoard` aggregator (TDD)

**Files:**
- Create: `ipad/Boutique360/Utilities/MorningBoard.swift`
- Create: `ipad/Boutique360Tests/MorningBoardTests.swift`

- [ ] **Step 1: Write the failing test suite.** Fixtures via JSON decode (no public inits on models — same technique as `OrderSlackTests.testReadyEventZeroesWorkViaResolver`). Test file skeleton with helpers:

```swift
import XCTest
@testable import Boutique360

/// R2 — every rule from the spec's Unit 1. today = 2026-07-28 throughout.
final class MorningBoardTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func d(_ y: Int, _ m: Int, _ dd: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: dd))!
    }
    private var today: Date { d(2026, 7, 28) }
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    private func order(_ num: String, status: String = "confirmed",
                       total: Double = 1000, event: String? = nil,
                       buffer: Int = 7, placed: String = "2026-07-01T10:00:00Z",
                       id: UUID = UUID()) -> Order {
        let eventLine = event.map { "\"event_date\":\"\($0)\"," } ?? ""
        let json = """
        {"id":"\(id.uuidString)",
         "boutique_id":"22222222-2222-2222-2222-222222222222",
         "order_number":"\(num)","customer_id":"33333333-3333-3333-3333-333333333333",
         "status":"\(status)","subtotal":\(total),"gst_amount":0,"total":\(total),
         "currency":"INR",\(eventLine)"alteration_buffer_days":\(buffer),
         "placed_at":"\(placed)",
         "created_at":"2026-07-01T10:00:00Z","updated_at":"2026-07-01T10:00:00Z"}
        """
        return try! decoder.decode(Order.self, from: json.data(using: .utf8)!)
    }

    private func card(orderId: UUID, status: String = "in_progress",
                      due: String? = "2026-08-10", id: UUID = UUID()) -> JobCard {
        let dueLine = due.map { "\"due_date\":\"\($0)\"," } ?? ""
        let json = """
        {"id":"\(id.uuidString)","boutique_id":"22222222-2222-2222-2222-222222222222",
         "job_number":"JC-\(id.uuidString.prefix(4))","order_id":"\(orderId.uuidString)",
         "status":"\(status)",\(dueLine)"fabric_list_json":[],"current_stage":0,
         "stages_progress_json":[],
         "created_at":"2026-07-01T10:00:00Z","updated_at":"2026-07-01T10:00:00Z"}
        """
        return try! decoder.decode(JobCard.self, from: json.data(using: .utf8)!)
    }

    private func readyEvent(cardId: UUID) -> JobCardEvent {
        try! decoder.decode(JobCardEvent.self, from: """
        {"id":"\(UUID().uuidString)","boutique_id":"22222222-2222-2222-2222-222222222222",
         "job_card_id":"\(cardId.uuidString)","event":"ready",
         "created_at":"2026-07-27T10:00:00Z"}
        """.data(using: .utf8)!)
    }

    private func alteration(orderId: UUID, status: String) -> Alteration {
        try! decoder.decode(Alteration.self, from: """
        {"id":"\(UUID().uuidString)","boutique_id":"22222222-2222-2222-2222-222222222222",
         "order_id":"\(orderId.uuidString)","round_number":1,"status":"\(status)",
         "request_notes":"n","created_at":"2026-07-20T10:00:00Z"}
        """.data(using: .utf8)!)
    }

    private func build(orders: [Order] = [],
                       cards: [UUID: JobCard] = [:],
                       events: [UUID: JobCardEvent] = [:],
                       alterations: [Alteration] = [],
                       designing: Int = 0,
                       appointments: Int = 0,
                       received: [UUID: Double] = [:],
                       failures: Set<MorningBoard.Input> = []) -> MorningBoard.Board {
        MorningBoard.build(orders: orders, jobCardsByOrder: cards,
                           latestEventByCard: events, openAlterations: alterations,
                           designingCount: designing, todaysAppointments: appointments,
                           customersById: [:], receivedByOrder: received,
                           failures: failures, today: today, calendar: cal)
    }

    // ── Tests (write ALL of these; expected values per spec rules) ──

    func testEmptyInputsZeroBoard() {
        let b = build()
        XCTAssertTrue(b.needsYou.isEmpty)
        XCTAssertEqual(b.atRiskCount, 0)
        XCTAssertEqual(b.moneyDue, .init(total: 0, orderCount: 0, oldestDays: 0))
        XCTAssertEqual(b.pipeline, .init(designing: 0, toStart: 0, withKarigar: 0, trialAlter: 0, ready: 0))
        XCTAssertEqual(b.todayFittings, 0)
        XCTAssertEqual(b.todayDeliveries, 0)
        XCTAssertTrue(b.failed.isEmpty)
    }

    func testSeverityOrdering() {
        // overdue (due 7/20, event 12/1) → late (event 8/16, due 8/10) →
        // atRisk (event 8/18, due 8/10) → ready (done card, balance 500)
        let o1 = order("BQ-OVD", event: "2026-12-01"); let c1 = card(orderId: o1.id, due: "2026-07-20")
        let o2 = order("BQ-LATE", event: "2026-08-16"); let c2 = card(orderId: o2.id, due: "2026-08-10")
        let o3 = order("BQ-RISK", event: "2026-08-18"); let c3 = card(orderId: o3.id, due: "2026-08-10")
        let o4 = order("BQ-RDY", total: 1000); let c4 = card(orderId: o4.id, status: "ready")
        let b = build(orders: [o4, o3, o2, o1],
                      cards: [o1.id: c1, o2.id: c2, o3.id: c3, o4.id: c4],
                      received: [o4.id: 500])
        XCTAssertEqual(b.needsYou.map(\.orderNumber), ["BQ-OVD", "BQ-LATE", "BQ-RISK", "BQ-RDY"])
        XCTAssertEqual(b.atRiskCount, 3)   // ready row excluded
        XCTAssertEqual(b.needsYou.last?.action, .deliverAndCollect(500))
    }

    func testReadyBeatsOverdue() {
        // Card past due BUT status ready → ready group, .deliver (paid), not chase.
        let o = order("BQ-RO", event: "2026-08-05")
        let c = card(orderId: o.id, status: "ready", due: "2026-07-20")
        let b = build(orders: [o], cards: [o.id: c], received: [o.id: 1000])
        XCTAssertEqual(b.needsYou.count, 1)
        XCTAssertEqual(b.needsYou[0].action, .deliver)
        XCTAssertEqual(b.atRiskCount, 0)
    }

    func testReadyEventCountsAsDone() {
        let o = order("BQ-EV")
        let c = card(orderId: o.id, status: "in_progress", due: "2026-07-20")
        let b = build(orders: [o], cards: [o.id: c],
                      events: [c.id: readyEvent(cardId: c.id)], received: [o.id: 1000])
        XCTAssertEqual(b.needsYou.first?.action, .deliver)   // not overdue/chase
        XCTAssertEqual(b.pipeline.ready, 1)
    }

    func testMoneyDueExcludesCancelledAndSubPaise() {
        let o1 = order("BQ-1", total: 1000)                 // 400 due
        let o2 = order("BQ-2", status: "cancelled", total: 5000)
        let o3 = order("BQ-3", total: 100)                  // paid to sub-paise drift
        let b = build(orders: [o1, o2, o3],
                      received: [o1.id: 600, o3.id: 99.999999])
        XCTAssertEqual(b.moneyDue.total, 400, accuracy: 0.01)
        XCTAssertEqual(b.moneyDue.orderCount, 1)
        XCTAssertEqual(b.moneyDue.oldestDays, 27)           // placed 7/1 → 7/28
    }

    func testPipelineLaneExclusivity() {
        let oNoCard = order("BQ-NC", status: "pending")
        let oDraft = order("BQ-DR"); let cDraft = card(orderId: oDraft.id, status: "draft")
        let oWork = order("BQ-WK"); let cWork = card(orderId: oWork.id, status: "issued")
        let oPacked = order("BQ-PK", status: "packed"); let cPackedReady = card(orderId: oPacked.id, status: "ready")
        let alts = [alteration(orderId: oWork.id, status: "requested"),
                    alteration(orderId: oWork.id, status: "completed")]  // completed NOT counted
        let b = build(orders: [oNoCard, oDraft, oWork, oPacked],
                      cards: [oDraft.id: cDraft, oWork.id: cWork, oPacked.id: cPackedReady],
                      alterations: alts, designing: 2)
        XCTAssertEqual(b.pipeline, .init(designing: 2, toStart: 2, withKarigar: 1,
                                         trialAlter: 1, ready: 1))   // packed+ready card = 1, not 2
        XCTAssertEqual(b.todayDeliveries, 1)                          // packed only
    }

    func testDegradationPassthroughAndPaymentsFailure() {
        let o = order("BQ-RDY2", total: 800)
        let c = card(orderId: o.id, status: "ready")
        let b = build(orders: [o], cards: [o.id: c], received: [:],
                      failures: [.payments])
        XCTAssertEqual(b.failed, [.payments])
        // payments failed → never a fake collect amount:
        XCTAssertEqual(b.needsYou.first?.action, .deliver)
    }

    func testWithinGroupTieBreakDeterministic() {
        // Two overdue orders, same days-overdue (due 7/20) → tie broken by
        // event date asc (8/10 before 12/1); a third with same event date
        // falls back to order number.
        let oA = order("BQ-B", event: "2026-12-01"); let cA = card(orderId: oA.id, due: "2026-07-20")
        let oB = order("BQ-A", event: "2026-08-10"); let cB = card(orderId: oB.id, due: "2026-07-20")
        let oC = order("BQ-AA", event: "2026-12-01"); let cC = card(orderId: oC.id, due: "2026-07-20")
        let b = build(orders: [oA, oB, oC], cards: [oA.id: cA, oB.id: cB, oC.id: cC])
        XCTAssertEqual(b.needsYou.map(\.orderNumber), ["BQ-A", "BQ-AA", "BQ-B"])
    }

    func testCustomerLookupMissRendersDash() {
        let o = order("BQ-CM", event: "2026-08-16")
        let c = card(orderId: o.id, due: "2026-08-10")
        let b = build(orders: [o], cards: [o.id: c])
        XCTAssertEqual(b.needsYou.first?.customerName, "—")
    }
}
```

- [ ] **Step 2: `xcodegen generate`, run — FAIL (type missing).**

- [ ] **Step 3: Implement `Utilities/MorningBoard.swift`** exactly per spec Unit 1 (the spec's rule list is the source of truth; key skeleton):

```swift
import Foundation

/// R2 — pure aggregator behind the Dashboard's exception-first morning board.
/// All rules specified in docs/superpowers/specs/2026-07-28-morning-board-design.md.
enum MorningBoard {
    enum Input: Hashable { case orders, jobCards, events, alterations, designs, payments, appointments }

    enum Action: Equatable {
        case chaseKarigar, decideToday
        case deliverAndCollect(Double), deliver
    }
    struct Item: Equatable, Identifiable {
        let id: UUID
        let orderNumber: String
        let customerName: String
        let garmentHint: String?
        let verdict: OrderSlack.Verdict
        let action: Action
        let balanceDue: Double
    }
    struct MoneyDue: Equatable {
        let total: Double; let orderCount: Int; let oldestDays: Int
        init(total: Double, orderCount: Int, oldestDays: Int) { ... }
    }
    struct Pipeline: Equatable { let designing, toStart, withKarigar, trialAlter, ready: Int; init(...) }
    struct Board: Equatable {
        let needsYou: [Item]; let moneyDue: MoneyDue; let atRiskCount: Int
        let pipeline: Pipeline; let todayFittings: Int; let todayDeliveries: Int
        let failed: Set<Input>
    }

    static func build(orders: [Order], jobCardsByOrder: [UUID: JobCard],
                      latestEventByCard: [UUID: JobCardEvent],
                      openAlterations: [Alteration], designingCount: Int,
                      todaysAppointments: Int, customersById: [UUID: Customer],
                      receivedByOrder: [UUID: Double], failures: Set<Input>,
                      today: Date = Date(), calendar: Calendar = .current) -> Board
}
```

Implementation notes binding the spec rules:
- done-signal helper: `card.status == .ready || card.status == .delivered || latestEvent?.event == .ready`.
- needsYou pass 1 (ready): done-signal && order.status ∉ {delivered, cancelled, returned}. Action: `failures.contains(.payments)` → `.deliver`; else balance = `Money.roundedToPaise(total − received)`; balance > 0 → `.deliverAndCollect(balance)` else `.deliver`.
- needsYou pass 2 (risk, remaining orders): `OrderSlack.verdict(for:jobCard:latestEvent:today:)` ∈ overdue/late/atRisk. Action overdue/late → `.chaseKarigar`, atRisk → `.decideToday`.
- Sort: group rank (overdue 0, late 1, atRisk 2, ready 3); within overdue/late by days desc, atRisk slack asc, ready balance desc; ties: eventDate asc nil-last, then orderNumber.
- atRiskCount = risk-group item count only.
- moneyDue over orders ∉ {cancelled, returned}, `Money.roundedToPaise(total − received) > 0`; oldestDays from `placedAt ?? createdAt` via `calendar.dateComponents([.day], from: startOfDay(oldest), to: startOfDay(today))`.
- Pipeline per order, precedence ready → withKarigar → toStart (spec rules verbatim, incl. draft-card → toStart). trialAlter = openAlterations count (caller passes only open ones, but filter `requested/in_progress` defensively). designing = passthrough.
- todayDeliveries = orders with status ∈ {packed, shipped}.
- customerName = `customersById[order.customerId]?.name ?? "—"`; garmentHint = job card's garmentType.

- [ ] **Step 4: Run — all 8 PASS. Step 5: Commit** `feat: MorningBoard pure aggregator + 8 tests`

**Chunk 1 gate:** MorningBoardTests + full suite green.

---

## Chunk 2: View + Dashboard integration + docs

### Task 3: `MorningBoardView`

**Files:**
- Create: `ipad/Boutique360/Features/Dashboard/MorningBoardView.swift`

- [ ] **Step 1: Implement** the stateless renderer (spec Unit 3). Structure:

```swift
import SwiftUI

/// R2 — exception-first board. Pure renderer of MorningBoard.Board;
/// degradation map per spec (— for failed inputs, real zeros for empty).
struct MorningBoardView: View {
    let board: MorningBoard.Board

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            tileRow
            if !board.needsYou.isEmpty && !boardBlocked { needsYouList }
            pipelineStrip
        }
    }
    private var boardBlocked: Bool {
        board.failed.contains(.orders) || board.failed.contains(.jobCards)
    }
    ...
}
```

- Tiles as `GroupBox`es in an `HStack` (follow `StatCard` styling in DashboardView): Today ("N fittings · M deliveries", em-dash when `.appointments` failed for fittings half), Money due (`Formatters.inr(total)` + "N orders · oldest Nd", em-dash when `.payments` failed), At risk (count, `.red` tint when > 0; "All on track" + green when 0 and !boardBlocked; em-dash when boardBlocked).
- Needs-you rows (≤6, `board.needsYou.prefix(6)`): MorningBoardView takes a second param `ordersById: [UUID: Order]` supplying `NavigationLink(value:)` payloads (Item stays pure). Row: `SlackBadge(verdict: item.verdict)` (non-compact) + VStack(customerName, orderNumber · garmentHint) + Spacer + action label (`chaseKarigar` → "Chase karigar" red, `decideToday` → "Decide today" orange, `deliverAndCollect(v)` → "Deliver + collect \(Formatters.inr(v))" green, `deliver` → "Deliver" green).
- Pipeline strip: HStack of 5 blocks, proportional width via `.frame(minWidth: 44, maxWidth: .infinity)` + `.layoutPriority(Double(max(count, 1)))`, count + caption label. Lane shows "—" when its input failed (trialAlter ← `.alterations`, designing ← `.designs`).
- Accessibility labels on tiles + rows (combine children, meaningful text).

- [ ] **Step 2: `xcodegen generate` + build green. Step 3: Commit** `feat: MorningBoardView renderer`

### Task 4: DashboardView integration

**Files:**
- Modify: `ipad/Boutique360/Features/Dashboard/DashboardView.swift` (state ~line 6-22, body ~line 26-40, `load()` ~line 290, `filterOverdue` ~line 406)

- [ ] **Step 1: State:** add

```swift
@State private var board: MorningBoard.Board?
@State private var ordersById: [UUID: Order] = [:]
```

- [ ] **Step 2: Body:** insert between `headerSection` and `todaysRevenueCard` (inside the `else` branch after `loading`):

```swift
if let board {
    MorningBoardView(board: board, ordersById: ordersById)
}
```

and add `.navigationDestination(for: Order.self) { o in OrderDetailView(order: o, customerName: customers[o.customerId]?.name) }` on the ScrollView (same pattern as OrdersListView:78).

- [ ] **Step 3: `load()` additions** (inside existing parallel fan-out, each `(result, failed)`):
  - job cards: `JobCardsService.forOrders(activeOrders.map(\.id), boutiqueId: bid)` — needs `bid = BoutiqueContext.shared.boutiqueId` (already the M4 pattern); run AFTER activeOrders resolves (sequential after the fan-out is fine — it's one query).
  - events: `JobCardEventsService.forJobCards(cards.map(\.id), boutiqueId: bid)` → latest per card dictionary (newest-first, first-wins — same as OrdersListView).
  - alterations: `AlterationsService.listOpen(boutiqueId: bid)`.
  - designs: `DesignsService.list()` → `designing = filter([.draft, .rendered, .shared_with_customer]).count`.
  - **Shared payments fetch:** replace `filterOverdue`'s internal `capturedSumsForOrders` call: hoist ONE call `PaymentsService.capturedSumsForOrders(nonCancelled.map(\.id))` where `nonCancelled = activeOrders.filter { ![.cancelled, .returned].contains($0.status) }`; build `receivedByOrder: [UUID: Double]`; pass the dictionary into BOTH `MorningBoard.build` and a refactored `filterOverdue(orders:receivedByOrder:)` that keeps its existing candidate filters (excludes pending, ≥7-day age) and threshold logic — its output must not change.
  - Track failures per input into a `Set<MorningBoard.Input>` — INCLUDING the pre-existing fan-out flags (`f3` orders-fetch → `.orders`, `f1` appointments → `.appointments`, payments-hoist failure → `.payments`), not just the four new fetches; OR everything into `anyFailed` for the banner.
  - Build: `self.board = MorningBoard.build(...)`; `self.ordersById = Dictionary(uniqueKeysWithValues: activeOrders.map { ($0.id, $0) })`.

- [ ] **Step 4: Full test suite + build — green.** Manual simulator check: Dashboard shows tiles; an order with event date + past-due job card appears in needs-you.

- [ ] **Step 5: Commit** `feat: R2 morning board wired into Dashboard (shared payments fetch, per-input degradation)`

### Task 5: Docs + push

- [ ] **Step 1:** `docs/app-map.md`: Dashboard row → "exception-first morning board (R2): tiles + needs-you + pipeline"; §7 R2 → ✅ SHIPPED. `README.md`: R2 roadmap line → ✅; test count updated. `CHANGELOG.md`: R2 entry. `CLAUDE.md`: speed-dial `Utilities/MorningBoard.swift`; test count.
- [ ] **Step 2:** Full suite one last time — expect ~163 tests green.
- [ ] **Step 3: Commit** `docs: R2 morning board shipped` **and push** `git push origin main:boutique-360-ipad-app`.
