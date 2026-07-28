# Slack Engine + Fabric Meters + Karigar Link Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship R1 (event-date slack engine + order surfacing), R4c (fabric-meters estimate in the Hinglish job-card brief), and R4d (karigar phone magic-link page with progress events).

**Architecture:** Migration adds `orders.event_date`/`alteration_buffer_days`, `job_cards.share_token`, and `job_card_events`. A pure `OrderSlack` enum computes honest verdicts (tested like `CustomerSpend`). SwiftUI surfacing: creation-time must-finish-by warning, slack badges on list/detail. R4d is a Deno Edge Function serving mobile HTML per token + accepting progress events that feed the engine's `jobCardDone`.

**Tech Stack:** Swift/SwiftUI iOS 17, XCTest (pure logic only), Supabase (Postgres 17, Edge Functions/Deno), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-07-28-slack-engine-karigar-link-design.md` — read it first; it defines verdict precedence, creation-time semantics, and the karigar page contract.

**Conventions that bind every task** (from CLAUDE.md): dates for DATE columns are `String` "YYYY-MM-DD" parsed via `Formatters.postgresDate`; views never call `SupabaseService.client` directly; boutique-scoped queries also pass `.eq("boutique_id", value: bid)` (RLS belt-and-braces); after adding any `.swift` file run `cd ipad && xcodegen generate`; commit after each task with the `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer.

**Branch/push strategy:** commits land on local `main` (established convention for this build phase). The remote push target is the branch `boutique-360-ipad-app` (`git push origin main:boutique-360-ipad-app`) — remote `main` holds an unrelated pre-app stub and must NOT be force-replaced. Push only at the end (Task 11).

**Build/test commands used throughout:**
```bash
cd ipad && xcodegen generate && xcodebuild -project Boutique360.xcodeproj -scheme Boutique360 \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build
# tests: same with `test -only-testing:Boutique360Tests/<Suite>`
```

---

## Chunk 1: Foundation — migration, models, engine

### Task 1: Migration 0028

**Files:**
- Create: `supabase/migrations/0028_event_slack_karigar.sql`

- [ ] **Step 1: Write the migration** (exact SQL from spec Unit 1):

```sql
-- 0028 — R1 slack inputs + R4d karigar link plumbing.
alter table public.orders
  add column if not exists event_date date,
  add column if not exists alteration_buffer_days int not null default 7;

alter table public.job_cards
  add column if not exists share_token uuid not null default gen_random_uuid();
create unique index if not exists job_cards_share_token_idx on public.job_cards(share_token);

create table if not exists public.job_card_events (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  job_card_id uuid not null references public.job_cards(id) on delete cascade,
  event text not null check (event in ('started','stitching_done','ready')),
  wip_photo_path text,
  created_at timestamptz not null default now()
);
create index if not exists job_card_events_card_idx on public.job_card_events(job_card_id, created_at);
alter table public.job_card_events enable row level security;
create policy "job_card_events_owner_read" on public.job_card_events for select to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "job_card_events_service" on public.job_card_events for all to service_role
  using (true) with check (true);

-- REPAIR + extend create_order_with_items.
-- The 0025 version did `insert into orders select * from
-- jsonb_populate_record(null::orders, p_order)`: jsonb_populate_record
-- yields explicit NULL for every key absent from the payload, and
-- `insert ... select *` writes those NULLs, BYPASSING column defaults —
-- so a payload without "id" violates the primary-key NOT NULL, and after
-- this migration a payload without "alteration_buffer_days" (any
-- already-installed app build) would violate its NOT NULL too.
-- Fix: explicit column list with coalesce() for every defaulted column.
-- Read supabase/migrations/0025_audit_fixes.sql lines 17-64 for the full
-- original body (items loop + inquiry link are kept verbatim) and replace
-- ONLY the header-insert statement with:
--
--   v_new := jsonb_populate_record(null::public.orders, p_order);
--   insert into public.orders
--     (id, boutique_id, order_number, customer_id, status, subtotal,
--      gst_amount, shipping, total, currency, magic_link_token,
--      fulfillment_method, placed_at, event_date, alteration_buffer_days,
--      created_at, updated_at)
--   values
--     (coalesce(v_new.id, gen_random_uuid()), v_new.boutique_id,
--      v_new.order_number, v_new.customer_id,
--      coalesce(v_new.status, 'pending'), coalesce(v_new.subtotal, 0),
--      coalesce(v_new.gst_amount, 0), v_new.shipping,
--      coalesce(v_new.total, 0), coalesce(v_new.currency, 'INR'),
--      v_new.magic_link_token, v_new.fulfillment_method, v_new.placed_at,
--      v_new.event_date, coalesce(v_new.alteration_buffer_days, 7),
--      coalesce(v_new.created_at, now()), coalesce(v_new.updated_at, now()))
--   returning * into v_order;
--
-- (v_new declared as public.orders. If 0025's status column has a CHECK
-- constraint listing allowed values, 'pending' is valid per the model.)
```

Include the full `create or replace function public.create_order_with_items(...)`
in the migration file — copy 0025's body, apply the header-insert replacement
above, keep everything else identical. **Verify after applying** (Step 2) with
a rollback-wrapped smoke call via MCP `execute_sql`:

```sql
begin;
select public.create_order_with_items(
  jsonb_build_object(
    'boutique_id', (select id from public.boutiques limit 1),
    'order_number', 'RPC-SMOKE-1',
    'customer_id', (select id from public.customers limit 1),
    'subtotal', 100, 'gst_amount', 5, 'total', 105),
  '[]'::jsonb, null);
rollback;
```

Expected: returns a row (id auto-generated, buffer 7) — no NOT NULL violation.

- [ ] **Step 2: Apply via Supabase MCP** (`apply_migration`, project `tdnwdlrkbrtoxjzcgusg`, name `event_slack_karigar`). If the MCP permission is denied, STOP and surface to the human — do not work around.

- [ ] **Step 3: Create the `karigar-wip` bucket** (private) via MCP `execute_sql`:
```sql
insert into storage.buckets (id, name, public) values ('karigar-wip','karigar-wip',false)
on conflict (id) do nothing;
```

- [ ] **Step 4: Commit** the SQL file: `git add supabase/migrations/0028_event_slack_karigar.sql && git commit -m "feat: migration 0028 — event_date, alteration buffer, karigar share token + events"`

### Task 2: Order model fields

**Files:**
- Modify: `ipad/Boutique360/Models/Order.swift` (struct Order ~line 62, NewOrder ~line 126)
- Test: `ipad/Boutique360Tests/ModelDecodingTests.swift` (append)

- [ ] **Step 1: Write the failing test** — append to `ModelDecodingTests`:

```swift
func testOrderDecodesEventDateAndBuffer() throws {
    let json = """
    {"id":"11111111-1111-1111-1111-111111111111",
     "boutique_id":"22222222-2222-2222-2222-222222222222",
     "order_number":"BQ-1","customer_id":"33333333-3333-3333-3333-333333333333",
     "status":"pending","subtotal":100,"gst_amount":5,"total":105,"currency":"INR",
     "event_date":"2026-09-19","alteration_buffer_days":14,
     "created_at":"2026-07-28T10:00:00Z","updated_at":"2026-07-28T10:00:00Z"}
    """.data(using: .utf8)!
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let order = try decoder.decode(Order.self, from: json)
    XCTAssertEqual(order.eventDate, "2026-09-19")
    XCTAssertEqual(order.alterationBufferDays, 14)
}

func testOrderDecodesWithoutEventDate() throws {
    // Pre-0028 rows / cached payloads: event_date absent, buffer defaults to 7.
    let json = """
    {"id":"11111111-1111-1111-1111-111111111111",
     "boutique_id":"22222222-2222-2222-2222-222222222222",
     "order_number":"BQ-2","customer_id":"33333333-3333-3333-3333-333333333333",
     "status":"pending","subtotal":100,"gst_amount":5,"total":105,"currency":"INR",
     "created_at":"2026-07-28T10:00:00Z","updated_at":"2026-07-28T10:00:00Z"}
    """.data(using: .utf8)!
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let order = try decoder.decode(Order.self, from: json)
    XCTAssertNil(order.eventDate)
    XCTAssertEqual(order.alterationBufferDays, 7)
}
```

- [ ] **Step 2: Run** `-only-testing:Boutique360Tests/ModelDecodingTests` — expect FAIL (no such property).

- [ ] **Step 3: Implement.** In `struct Order` add below `fulfillmentMethod`:

```swift
var eventDate: String?            // YYYY-MM-DD — customer's occasion (R1)
var alterationBufferDays: Int     // R1 — absent-key tolerant, defaults 7
```

CodingKeys: `case eventDate = "event_date"`, `case alterationBufferDays = "alteration_buffer_days"`. `Order.swift` has a custom `init(from:)` at ~line 160 — add `alterationBufferDays = try c.decodeIfPresent(Int.self, forKey: .alterationBufferDays) ?? 7` and the `eventDate` decode there. In `NewOrder` add `let event_date: String?` and `let alteration_buffer_days: Int`. The repaired RPC (Task 1) coalesces both columns, so old app builds that omit them keep working.

- [ ] **Step 4: Fix all `NewOrder(` call sites** — `grep -rn "NewOrder(" ipad/` and add the two args (`event_date: nil, alteration_buffer_days: 7` where no UI exists yet).

- [ ] **Step 5: Run tests** — expect PASS. Build the app target too.

- [ ] **Step 6: Commit** `feat: Order.eventDate + alterationBufferDays`

### Task 3: JobCard.shareToken + JobCardEvent model

**Files:**
- Modify: `ipad/Boutique360/Models/JobCard.swift`
- Test: `ipad/Boutique360Tests/ModelDecodingTests.swift` (append)

- [ ] **Step 1: Failing test:**

```swift
func testJobCardEventDecodes() throws {
    let json = """
    {"id":"44444444-4444-4444-4444-444444444444",
     "boutique_id":"22222222-2222-2222-2222-222222222222",
     "job_card_id":"55555555-5555-5555-5555-555555555555",
     "event":"ready","wip_photo_path":null,
     "created_at":"2026-07-28T10:00:00Z"}
    """.data(using: .utf8)!
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let e = try decoder.decode(JobCardEvent.self, from: json)
    XCTAssertEqual(e.event, .ready)
    XCTAssertNil(e.wipPhotoPath)
}
```

- [ ] **Step 2: Run — FAIL.**

- [ ] **Step 3: Implement** in `JobCard.swift`: add `var shareToken: UUID?` to `JobCard` (+ CodingKey `share_token`; optional so pre-migration cached rows tolerate absence), and append:

```swift
/// R4d — karigar progress event, inserted by the job-card-view Edge Function.
/// Kind is strict (no unknown-case fallback): the DB check constraint
/// guarantees exactly these three values.
struct JobCardEvent: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case started
        case stitchingDone = "stitching_done"
        case ready
    }
    let id: UUID
    var boutiqueId: UUID
    var jobCardId: UUID
    var event: Kind
    var wipPhotoPath: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, event
        case boutiqueId = "boutique_id"
        case jobCardId = "job_card_id"
        case wipPhotoPath = "wip_photo_path"
        case createdAt = "created_at"
    }
}
```

- [ ] **Step 4: Run — PASS. Step 5: Commit** `feat: JobCard.shareToken + JobCardEvent model`

### Task 4: OrderSlack engine (TDD — the heart of R1)

**Files:**
- Create: `ipad/Boutique360/Utilities/OrderSlack.swift`
- Create: `ipad/Boutique360Tests/OrderSlackTests.swift`

- [ ] **Step 1: Write the full failing test suite first** (spec's test list, verbatim behaviors). Helper builds dates via `DateComponents` + gregorian calendar like `CustomerSpendTests`:

```swift
import XCTest
@testable import Boutique360

final class OrderSlackTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func d(_ y: Int, _ m: Int, _ dd: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: dd))!
    }
    // today = 2026-07-28 in all tests
    private var today: Date { d(2026, 7, 28) }

    private func verdict(event: Date?, due: Date?, done: Bool = false,
                         status: OrderStatus = .confirmed,
                         fulfillment: FulfillmentMethod? = .pickup,
                         buffer: Int = 7) -> OrderSlack.Verdict {
        OrderSlack.evaluate(eventDate: event, jobCardDue: due, jobCardDone: done,
                            orderStatus: status, fulfillment: fulfillment,
                            alterationBufferDays: buffer, today: today, calendar: cal)
    }

    func testNoEventDate() {
        XCTAssertEqual(verdict(event: nil, due: d(2026,8,10)), .noEvent)
    }
    func testCancelledIsNoEvent() {
        XCTAssertEqual(verdict(event: d(2026,9,1), due: d(2026,8,1), status: .cancelled), .noEvent)
    }
    func testEventButNoJobCardDueIsNoPlan() {
        XCTAssertEqual(verdict(event: d(2026,9,1), due: nil), .noPlan)
    }
    func testComfortable() {
        // event 9/30 (64d out), due 8/10 (13d work), buffer 7, pickup 0 → slack 44
        XCTAssertEqual(verdict(event: d(2026,9,30), due: d(2026,8,10)), .comfortable(days: 44))
    }
    func testAtRiskAtSlackZeroAndOne() {
        // due 8/10 → work 13. buffer 7. event = today+20 → slack 0
        XCTAssertEqual(verdict(event: d(2026,8,17), due: d(2026,8,10)), .atRisk(days: 0))
        XCTAssertEqual(verdict(event: d(2026,8,18), due: d(2026,8,10)), .atRisk(days: 1))
    }
    func testLate() {
        XCTAssertEqual(verdict(event: d(2026,8,16), due: d(2026,8,10)), .late(days: 1))
    }
    func testShipAddsThreeDays() {
        // same as the slack-0 pickup case, but ship → late by 3
        XCTAssertEqual(verdict(event: d(2026,8,17), due: d(2026,8,10), fulfillment: .ship),
                       .late(days: 3))
    }
    func testOverdueUnfinishedBeatsPositiveSlack() {
        // due yesterday, not done, event far away — raw slack would be big + green
        XCTAssertEqual(verdict(event: d(2026,12,1), due: d(2026,7,27)),
                       .overdue(daysOverdue: 1))
    }
    func testDoneJobPastDueIsNotOverdue() {
        // done=true zeroes work; event 8/10 (13d out) − 0 − 7 → comfortable 6
        XCTAssertEqual(verdict(event: d(2026,8,10), due: d(2026,7,20), done: true),
                       .comfortable(days: 6))
    }
    func testDeliveredOrderWithUnclosedPastDueCardIsNotOverdue() {
        XCTAssertEqual(verdict(event: d(2026,8,10), due: d(2026,7,20), status: .delivered),
                       .comfortable(days: 6))
    }
    func testMustFinishByArithmetic() {
        let mf = OrderSlack.mustFinishBy(eventDate: d(2026,9,19), fulfillment: .ship,
                                         alterationBufferDays: 7, calendar: cal)
        XCTAssertEqual(mf, d(2026,9,9))   // 19 − 7 buffer − 3 ship
    }
    func testMustFinishByNilWithoutEvent() {
        XCTAssertNil(OrderSlack.mustFinishBy(eventDate: nil, fulfillment: .pickup,
                                             alterationBufferDays: 7, calendar: cal))
    }
    func testRushThresholdBoundary() {
        // Exactly minimumProductionDays (7) of production time is NOT rush;
        // 6 is. This pins the `<` (not `<=`) comparison used by the create view.
        XCTAssertFalse(7 < OrderSlack.minimumProductionDays)
        XCTAssertTrue(6 < OrderSlack.minimumProductionDays)
    }
}
```

Additionally, in **Task 10** (after the resolver gains `latestEvent:`), append one
more test to this suite exercising the resolver path:

```swift
func testReadyEventZeroesWorkViaResolver() throws {
    // Build Order + JobCard via JSON decode (see ModelDecodingTests helpers),
    // event 30d out, job due 20d out (work 20, buffer 7 → slack 3 without
    // event), latestEvent .ready → done → slack 30-0-7 = comfortable(23).
    // Assert OrderSlack.verdict(for:jobCard:latestEvent:today:) == .comfortable(days: 23).
}
```

- [ ] **Step 2: `xcodegen generate`, run suite — FAIL (type missing).**

- [ ] **Step 3: Implement** `Utilities/OrderSlack.swift` exactly per spec Unit 2. Verdict precedence: cancelled/returned → noEvent · event nil → noEvent · due nil → noPlan · overdue guard (`due < today && !done && !delivered`) → overdue · else classify. Constants `shipDeliveryDays = 3`, `minimumProductionDays = 7`. All day math via `calendar.startOfDay` + `dateComponents([.day])` so time-of-day never shifts results:

```swift
import Foundation

/// R1 — honest per-order deadline slack. Pure; all inputs injected.
/// Verdict precedence and formula are specified in
/// docs/superpowers/specs/2026-07-28-slack-engine-karigar-link-design.md.
enum OrderSlack {
    static let shipDeliveryDays = 3
    static let minimumProductionDays = 7

    enum Verdict: Equatable {
        case noEvent
        case noPlan
        case overdue(daysOverdue: Int)
        case late(days: Int)
        case atRisk(days: Int)
        case comfortable(days: Int)
    }

    static func evaluate(eventDate: Date?, jobCardDue: Date?, jobCardDone: Bool,
                         orderStatus: OrderStatus, fulfillment: FulfillmentMethod?,
                         alterationBufferDays: Int, today: Date,
                         calendar: Calendar = .current) -> Verdict {
        if orderStatus == .cancelled || orderStatus == .returned { return .noEvent }
        guard let event = eventDate else { return .noEvent }
        guard let due = jobCardDue else { return .noPlan }

        let d0 = calendar.startOfDay(for: today)
        let dEvent = calendar.startOfDay(for: event)
        let dDue = calendar.startOfDay(for: due)
        let delivered = orderStatus == .delivered
        let done = jobCardDone || delivered

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

    /// event − buffer − delivery. The date production must finish by.
    static func mustFinishBy(eventDate: Date?, fulfillment: FulfillmentMethod?,
                             alterationBufferDays: Int,
                             calendar: Calendar = .current) -> Date? {
        guard let event = eventDate else { return nil }
        let deliveryDays = (fulfillment == .ship) ? shipDeliveryDays : 0
        return calendar.date(byAdding: .day, value: -(alterationBufferDays + deliveryDays),
                             to: calendar.startOfDay(for: event))
    }
}
```

- [ ] **Step 4: Run — all 12 PASS. Step 5: Commit** `feat: OrderSlack pure engine + 12 tests`

**Chunk 1 gate:** full test suite green, build green, 4 commits.

---

## Chunk 2: iPad surfacing + R4c

### Task 5: SlackBadge view + batched job-card fetch

**Files:**
- Create: `ipad/Boutique360/Features/Orders/SlackBadge.swift`
- Modify: `ipad/Boutique360/Services/JobCardsService.swift` (append one func)

- [ ] **Step 1: Add `JobCardsService.forOrders`** (single query, no N+1):

```swift
/// R1 — batch fetch for slack badges: one query for a page of orders.
/// boutiqueId: RLS belt-and-braces per CLAUDE.md (callers pass ctx.boutiqueId).
static func forOrders(_ orderIds: [UUID], boutiqueId: UUID) async throws -> [JobCard] {
    guard !orderIds.isEmpty else { return [] }
    return try await SupabaseService.client.from("job_cards")
        .select()
        .eq("boutique_id", value: boutiqueId)
        .in("order_id", values: orderIds)
        .execute()
        .value
}
```

(All call sites in Tasks 6/10 pass `ctx.boutiqueId` — guard-let it per existing view patterns. Same belt-and-braces on `JobCardEventsService.list/forJobCards` in Task 10.)

```swift
```

- [ ] **Step 2: Create `SlackBadge.swift`** — one shared view (R2 reuses it) plus the Order→Verdict resolver:

```swift
import SwiftUI

/// R1 — colored capsule for an order's slack verdict. Shared by list + detail
/// (and later the R2 morning board). In compact mode, noEvent renders nothing.
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
    /// karigar event, using app conventions (postgresDate parsing, completed
    /// status / completedAt / ready-event as the done-signal).
    static func verdict(for order: Order, jobCard: JobCard?,
                        latestEvent: JobCardEvent? = nil,
                        today: Date = Date()) -> Verdict {
        let event = order.eventDate.flatMap { Formatters.postgresDate.date(from: $0) }
        let due = jobCard?.dueDate.flatMap { Formatters.postgresDate.date(from: $0) }
        let done = jobCard?.completedAt != nil || latestEvent?.event == .ready
        return evaluate(eventDate: event, jobCardDue: due, jobCardDone: done,
                        orderStatus: order.status, fulfillment: order.fulfillmentMethod,
                        alterationBufferDays: order.alterationBufferDays, today: today)
    }
}
```

(Implementer: check `enum JobCardStatus` in `JobCard.swift` — if it has a terminal case like `.completed`/`.delivered`, OR it into `done`. `completedAt != nil` is the reliable signal per the model.)

- [ ] **Step 3: `xcodegen generate` + build — green. Step 4: Commit** `feat: SlackBadge + JobCardsService.forOrders`

### Task 6: Badges on OrdersListView + OrderDetailView

**Files:**
- Modify: `ipad/Boutique360/Features/Orders/OrdersListView.swift` (state ~lines 4-10, row ~line 37, `load()` ~line 117)
- Modify: `ipad/Boutique360/Features/Orders/OrderDetailView.swift` (header area)

- [ ] **Step 1: OrdersListView** — add:

```swift
@State private var jobCardsByOrder: [UUID: JobCard] = [:]
```

In `load()` after the orders fetch (failure of this secondary fetch must NOT clobber the orders list — badges just degrade to `.noPlan`):

```swift
let cards = (try? await JobCardsService.forOrders(orders.map(\.id))) ?? []
jobCardsByOrder = Dictionary(cards.compactMap { c in c.orderId.map { ($0, c) } },
                             uniquingKeysWith: { a, _ in a })
```

(This task compiles standalone. Karigar events fold into the badge inputs in Task 10 Step 3 — do NOT reference `JobCardEventsService` here; it doesn't exist yet.)

In the order row, next to the status capsule:
`SlackBadge(verdict: OrderSlack.verdict(for: o, jobCard: jobCardsByOrder[o.id]), compact: true)`

- [ ] **Step 2: OrderDetailView** — add `@State private var jobCard: JobCard?`; in its existing `.task`, `jobCard = try? await JobCardsService.forOrders([order.id]).first`. Render near the status header:

```swift
HStack {
    SlackBadge(verdict: OrderSlack.verdict(for: current, jobCard: jobCard))
    if let ev = current.eventDate {
        Text("Event \(ev) · buffer \(current.alterationBufferDays)d")
            .font(.caption2).foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 3: Build green. Step 4: Commit** `feat: slack badges on orders list + detail`

### Task 7: OrderCreateView — event date + buffer + must-finish-by

**Files:**
- Modify: `ipad/Boutique360/Features/Orders/OrderCreateView.swift` (state ~lines 9-21, form body, `NewOrder(` ~line 125)

- [ ] **Step 1: Add state:**

```swift
@State private var hasEventDate = false
@State private var eventDate = Date()
@State private var alterationBufferDays = 7
```

- [ ] **Step 2: Add a Form section** (after the fulfillment picker):

```swift
Section("Event deadline") {
    Toggle("Tied to an event date", isOn: $hasEventDate)
    if hasEventDate {
        DatePicker("Event date", selection: $eventDate, in: Date()..., displayedComponents: .date)
        Stepper("Alteration buffer: \(alterationBufferDays) days", value: $alterationBufferDays, in: 0...30)
        mustFinishByLine
    }
}
```

with this helper (warn, never block — Save's `disabled` condition unchanged):

```swift
@ViewBuilder private var mustFinishByLine: some View {
    if let mf = OrderSlack.mustFinishBy(eventDate: eventDate,
                                        fulfillment: fulfillmentMethod,
                                        alterationBufferDays: alterationBufferDays) {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: mf).day ?? 0
        if days < 0 {
            Label("Won't fit: the event is inside the alteration + delivery buffer.",
                  systemImage: "exclamationmark.octagon.fill")
                .font(.caption).foregroundStyle(.red)
        } else if days < OrderSlack.minimumProductionDays {
            Label("Production must finish by \(mf.formatted(date: .abbreviated, time: .omitted)) — only \(days) days. Rush order.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red)
        } else {
            Label("Production must finish by \(mf.formatted(date: .abbreviated, time: .omitted)) — \(days) days from today.",
                  systemImage: "calendar.badge.clock")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 3: Thread into `NewOrder(`:**
`event_date: hasEventDate ? Formatters.postgresDate.string(from: eventDate) : nil, alteration_buffer_days: alterationBufferDays`

- [ ] **Step 4: Build green. Step 5: Commit** `feat: event date + buffer + must-finish-by warning at order creation`

### Task 8: R4c — fabric meters in the tailor brief

**Files:**
- Modify: `ipad/Boutique360/Services/GeminiService.swift` (`PromptTemplates.tailorBrief`, ~line 299)
- Test: check `ls ipad/Boutique360Tests/ | grep -i prompt` — append to the existing prompt-template test file if one exists, else create `PromptTemplatesTests.swift`

- [ ] **Step 1: Failing test:**

```swift
func testTailorBriefAsksForFabricMetersEstimate() {
    let brief = PromptTemplates.tailorBrief(
        garmentType: "lehenga", occasion: "sangeet", customerNotes: nil,
        fabricList: [], measurements: ["bust": 36], embellishments: nil,
        dueDate: nil, karigarName: nil)
    XCTAssertTrue(brief.contains("meter"), "brief must request a meters estimate")
    XCTAssertTrue(brief.contains("andaaza"), "estimate must be marked approximate in Hinglish")
}
```

- [ ] **Step 2: Run — FAIL. Step 3: Implement** — inside `tailorBrief`, matching its existing Hinglish tone, add:

```swift
let metersLine = " Kapde ki zaroorat ka andaaza bhi likhna — kitne meter fabric lagega is \(garment) ke liye, measurements dekh kar. Saaf likhna ki ye sirf andaaza hai — cutting se pehle khud check karo."
```

and concatenate `metersLine` into the returned prompt string.

- [ ] **Step 4: Run — PASS. Step 5: Commit** `feat: R4c fabric-meters estimate in tailor brief prompt`

**Chunk 2 gate:** full suite green, build green, manual check: create an order with an event 5 days out → rush warning shows.

---

## Chunk 3: R4d — karigar magic-link

### Task 9: Edge Function `job-card-view`

**Files:**
- Create: `supabase/functions/job-card-view/index.ts`

Contract (spec Unit 5): `GET /job-card-view/⟨token⟩` → mobile HTML; `POST /job-card-view/⟨token⟩/event` → insert event. Service-role client; **the token IS the auth** (deploy with `verify_jwt: false`; say so in the header comment).

- [ ] **Step 1: Write the function.** Note: there is NO `supabase/functions/` directory in the repo (the purge function lives only in Supabase cloud) — create the directory. The skeleton below is complete for client setup; if you want the deployed purge function as a style reference, fetch it via MCP `get_edge_function`. Skeleton:

```ts
// job-card-view — karigar-facing magic-link page. The share_token IS the
// capability: anyone with the link can view this job card and post progress
// (same trust model as forwarding the PDF on WhatsApp). Deployed with
// verify_jwt=false. Owner revokes by regenerating the token.
import { createClient } from "npm:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

const EVENTS = ["started", "stitching_done", "ready"] as const;
const LABELS: Record<string, string> = {
  started: "Shuru kiya", stitching_done: "Silai poori", ready: "Taiyaar hai",
};
const MAX_PHOTO_BYTES = 5 * 1024 * 1024;
const RATE_LIMIT_PER_DAY = 30;

Deno.serve(async (req) => {
  const url = new URL(req.url);
  // pathname: /job-card-view/<token>[/event]
  const parts = url.pathname.split("/").filter(Boolean);
  const token = parts[1];
  const isEvent = parts[2] === "event";
  if (!token) return new Response("Not found", { status: 404 });

  const { data: card } = await supabase.from("job_cards")
    .select("*").eq("share_token", token).maybeSingle();
  if (!card) return new Response("Link galat hai ya band ho gaya hai.", { status: 404 });

  if (req.method === "POST" && isEvent) return handleEvent(req, card, url);
  if (req.method === "GET" && !isEvent) return renderPage(card);
  return new Response("Method not allowed", { status: 405 });
});
```

`handleEvent(req, card, url)`:
1. `const form = await req.formData()`; `const event = String(form.get("event"))`; not in EVENTS → 400.
2. Rate limit: `select id` with `count: "exact", head: true` on `job_card_events` where `job_card_id = card.id` and `created_at > new Date(Date.now() - 86400_000).toISOString()`; count ≥ 30 → 429 `"Aaj ke liye limit ho gayi — kal try karo."`.
3. Optional `photo`: `form.get("photo")` as File; if present — `size > MAX_PHOTO_BYTES` → 413; `type` not `image/jpeg`/`image/png` → 415; else upload to bucket `karigar-wip`, path `${card.id}/${crypto.randomUUID()}.${type === "image/png" ? "png" : "jpg"}`.
4. Insert `{ boutique_id: card.boutique_id, job_card_id: card.id, event, wip_photo_path }`.
5. Respond `303` redirect to the GET URL (PRG so refresh doesn't repost; double-taps are harmless — events are append-only).

`renderPage(card)`:
1. Latest events: `select * ... order created_at desc limit 10`.
2. Customer first name only: `select name from customers where id = card.customer_id` → `.split(" ")[0]`; never render phone/address.
3. Signed URLs (1-hour TTL) via `supabase.storage.from(bucket).createSignedUrl(path, 3600)` for `render_image_path` / `sketch_image_path` when present, and for each event's `wip_photo_path`.
4. Return HTML, `Content-Type: text/html; charset=utf-8`, `lang="hi-Latn"`: inline CSS only, system font stack, base font ≥18px, max-width 480px. Sections: job number + garment + occasion header, due date big and bold, first name, render image (`<img style="max-width:100%">`), fabric list, measurements table, `hindi_brief` in a bordered block, then three `<form method="post" action=".../event">` blocks — one per event kind, each a full-width ≥56px button, the kind matching the latest event visually highlighted — sharing one `<input type="file" name="photo" accept="image/jpeg,image/png">` per form. Recent-updates list at the bottom (label + time + thumbnail).

- [ ] **Step 2: Deploy via Supabase MCP** `deploy_edge_function` (name `job-card-view`, `verify_jwt: false`).

- [ ] **Step 3: Smoke test with curl:** get a real token via MCP `execute_sql` (`select share_token from job_cards limit 1`); then: GET with token → 200 HTML; GET bad token → 404; POST `-F event=started` → 303 and event row exists (verify via `execute_sql`); POST `-F event=bogus` → 400.

- [ ] **Step 4: Commit** `feat: R4d karigar job-card-view Edge Function`

### Task 10: iPad side — events service, timeline, share + regenerate

**Files:**
- Create: `ipad/Boutique360/Services/JobCardEventsService.swift`
- Modify: `ipad/Boutique360/Services/StorageService.swift` (bucket enum + case `karigarWip = "karigar-wip"`)
- Modify: `ipad/Boutique360/Features/JobCards/JobCardPreviewView.swift`
- Modify: `ipad/Boutique360/Features/Orders/OrdersListView.swift` (events half of the badge inputs)
- Modify: `ipad/Boutique360/Features/Orders/OrderTimelineView.swift`

- [ ] **Step 1: Service:**

```swift
import Foundation
import Supabase

enum JobCardEventsService {
    static func list(jobCardId: UUID) async throws -> [JobCardEvent] {
        try await SupabaseService.client.from("job_card_events")
            .select().eq("job_card_id", value: jobCardId)
            .order("created_at", ascending: false)
            .execute().value
    }

    /// Batch for list badges: events for a page of cards, newest first.
    static func forJobCards(_ ids: [UUID]) async throws -> [JobCardEvent] {
        guard !ids.isEmpty else { return [] }
        return try await SupabaseService.client.from("job_card_events")
            .select().in("job_card_id", values: ids)
            .order("created_at", ascending: false)
            .execute().value
    }

    /// Revokes previously shared links by rotating the capability token.
    static func regenerateToken(jobCardId: UUID) async throws -> UUID {
        struct Row: Decodable { let share_token: UUID }
        let row: Row = try await SupabaseService.client.from("job_cards")
            .update(["share_token": UUID().uuidString])
            .eq("id", value: jobCardId)
            .select("share_token").single().execute().value
        return row.share_token
    }

    static func shareURL(token: UUID) -> URL {
        Config.supabaseURL
            .appendingPathComponent("functions/v1/job-card-view/\(token.uuidString.lowercased())")
    }
}
```

- [ ] **Step 2: JobCardPreviewView** — add:
  - "Share karigar link" button: when `card.shareToken` is nil (stale cached card), re-fetch via `JobCardsService.get(id:)` into local state first; then `ShareLink(item: JobCardEventsService.shareURL(token: token))`. **Deliberate deviation from spec Unit 5's wa.me wording:** the karigar's phone number isn't modeled (only `assignedKarigarId`), so `WhatsAppShareHelper.open(phone:)` has no target — `ShareLink` lets the owner pick the WA chat in the share sheet, which is the same one-tap outcome. Note this in the commit message.
  - "Regenerate link" behind a `confirmationDialog` whose message states: "Old shared links will stop working." On confirm, call `regenerateToken`, update local state.
  - "Updates from karigar" section: `JobCardEventsService.list` rows — Kind label (Shuru kiya / Silai poori / Taiyaar hai), `createdAt` relative time, WIP thumbnail via `StorageService.signedURL(bucket: .karigarWip, path:)` (add the bucket case).
  - Load-error surfacing per house pattern (banner + retry), mutations via `do/catch` + `ErrorBus.shared.report`.

- [ ] **Step 3: Fold events into badges** — in `OrdersListView.load()` add the `latestEventByCard` fetch from Task 6 Step 1's commented-out half, and pass `latestEvent: latestEventByCard[card.id]` into `OrderSlack.verdict(for:jobCard:latestEvent:)`. In `OrderTimelineView`, merge karigar events into the displayed sequence (newest first) with a distinct icon (`figure.walk` / `scissors` / `checkmark.seal`).

- [ ] **Step 4: `xcodegen generate` + full test suite + build — green. Step 5: Commit** `feat: karigar events on iPad — service, timeline, share + regenerate link`

### Task 11: Verify end-to-end + docs

- [ ] **Step 1: Run FULL test suite** — expect ~152 tests (137 + new), 0 failures.
- [ ] **Step 2: Simulator smoke:** create order with event 5 days out → rush warning; orders list shows badges; job card → share link yields URL; `curl` the URL → HTML; `curl -F event=ready` → iPad timeline shows the event and the order's badge recomputes with work = 0.
- [ ] **Step 3: Docs:** `docs/app-map.md` (§2 Orders/JobCards key actions, §5 add the Edge Function row, §7 mark R1/R4c/R4d ✅), `docs/api-rpcs.md` (job-card-view GET/POST contract), `CLAUDE.md` (speed-dial: `OrderSlack.swift`, `JobCardEventsService.swift`; migration count 28), `CHANGELOG.md` entry.
- [ ] **Step 4: Commit** `docs: R1/R4c/R4d shipped — app map, API ref, changelog`
- [ ] **Step 5: Push** `git push origin main:boutique-360-ipad-app`.
