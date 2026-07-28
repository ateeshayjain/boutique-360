# Lock the Look + Change-Orders (R3) Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Freeze an order's spec into an immutable lock (design/render, fabric, pinned measurement, price breakup, event plan, advance); post-lock price/date changes only via append-only change-orders applied atomically.

**Architecture:** Migration 0029 adds `orders.design_id`, `order_locks`, `change_orders` and two RPCs (`lock_order`, `apply_change_order`) — **the SQL in the spec's Unit 1 is normative and complete; copy it verbatim.** Swift side: models, pure `LockGate`, `OrderLocksService` (RPC wrappers), `LockSheet` + `LockSummarySheet` UI, OrderDetailView gating.

**Tech Stack:** Swift/SwiftUI iOS 17, XCTest pure-logic-only, Supabase (Postgres RPCs applied via MCP), existing services (Payments/Designs/DesignRenders/Measurements/OrderSlack).

**Spec:** `docs/superpowers/specs/2026-07-28-lock-screen-design.md` — read it FIRST. Its SQL (incl. lock_order's order-read guard + status gate, apply_change_order's lock-precondition + subtotal floor + exact total invariant, and the RLS policy SQL) must be copied exactly, not re-derived.

**Conventions:** boutique-scoped queries `.eq("boutique_id", …)`; `Formatters.postgresDate` for DATE strings; `xcodegen generate` after new files; commit per task, trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`; push once at the end to `origin main:boutique-360-ipad-app`.

**Build/test:**
```bash
cd ipad && xcodegen generate && xcodebuild -project Boutique360.xcodeproj -scheme Boutique360 \
  -destination 'platform=iOS Simulator,id=092B3063-9443-4E76-AD24-3918E9A0695C' test -only-testing:Boutique360Tests/<Suite>
```

---

## Chunk 1: Migration + models + LockGate

### Task 1: Migration 0029 + live smoke

**Files:**
- Create: `supabase/migrations/0029_order_locks_change_orders.sql` — the spec Unit 1 SQL verbatim (alter orders + order_locks + policies + change_orders + policies + `lock_order` + `apply_change_order`).

- [ ] **Step 1:** Write the file (copy from spec Unit 1).
- [ ] **Step 2:** Apply via Supabase MCP `apply_migration` (project `tdnwdlrkbrtoxjzcgusg`, name `order_locks_change_orders`). If denied, STOP and surface.
- [ ] **Step 3: Live smoke via MCP `execute_sql` — sequential `DO` block, NOT CTEs.** (Unreferenced SELECT CTEs are never executed by Postgres — a CTE-chained smoke silently tests nothing. plpgsql statements are guaranteed ordered and all-executed.)

```sql
begin;
do $$
declare
  v_order public.orders;
  v_lock public.order_locks;
  v_co public.change_orders;
begin
  v_order := public.create_order_with_items(
    jsonb_build_object(
      'boutique_id', (select id from public.boutiques limit 1),
      'order_number', 'R3-SMOKE-' || floor(random()*100000)::text,
      'customer_id', (select id from public.customers limit 1),
      'subtotal', 1000, 'gst_amount', 50, 'total', 1050,
      'event_date', '2026-09-19'),
    '[]'::jsonb, null);

  v_lock := public.lock_order(jsonb_build_object(
    'boutique_id', v_order.boutique_id,
    'order_id', v_order.id,
    'advance_amount', 500));

  -- (1) positive delta + new date: 5% effective rate preserved
  v_co := public.apply_change_order(v_order.id, 'sleeves added', 1000, '2026-09-25');
  select * into v_order from public.orders where id = v_order.id;
  assert v_order.subtotal = 2000, 'subtotal: ' || v_order.subtotal;
  assert v_order.gst_amount = 100.00, 'gst: ' || v_order.gst_amount;
  assert v_order.total = 2100.00, 'total: ' || v_order.total;
  assert v_order.event_date = '2026-09-25', 'event: ' || v_order.event_date;

  -- (2) negative delta WITHIN the floor succeeds
  v_co := public.apply_change_order(v_order.id, 'simplified border', -500, null);
  select * into v_order from public.orders where id = v_order.id;
  assert v_order.subtotal = 1500 and v_order.gst_amount = 75.00 and v_order.total = 1575.00,
    'negative-delta math: ' || v_order.subtotal || '/' || v_order.gst_amount || '/' || v_order.total;

  -- (3) floor breach raises
  begin
    v_co := public.apply_change_order(v_order.id, 'impossible refund', -99999, null);
    raise exception 'floor breach did NOT raise';
  exception when others then
    assert sqlerrm like '%negative%', 'unexpected: ' || sqlerrm;
  end;

  -- (4) double lock → unique violation
  begin
    v_lock := public.lock_order(jsonb_build_object(
      'boutique_id', v_order.boutique_id, 'order_id', v_order.id, 'advance_amount', 1));
    raise exception 'double lock did NOT raise';
  exception when unique_violation then null;
  end;

  raise notice 'R3 smoke OK';
end $$;
rollback;
```

Then two standalone failure smokes (each its own begin/DO/rollback):
- `apply_change_order` on a fresh UNLOCKED order → assert sqlerrm like `%not locked%`.
- `lock_order` on an order first set to `status='cancelled'` → assert sqlerrm like `%pending/confirmed%`.

- [ ] **Step 4: Commit** `feat: migration 0029 — order_locks, change_orders, lock_order + apply_change_order RPCs (live-smoked)`

### Task 2: Models + decode tests

**Files:**
- Modify: `ipad/Boutique360/Models/Order.swift` (struct Order + custom init + NewOrder untouched — design_id is NOT in NewOrder; the lock RPC patches it)
- Create: `ipad/Boutique360/Models/OrderLock.swift`
- Test: `ipad/Boutique360Tests/ModelDecodingTests.swift` (append)

- [ ] **Step 1: Failing tests** (append):

```swift
func testOrderDecodesDesignId() throws {
    // Reuse the JSON from testOrderDecodesEventDateAndBuffer + add:
    //   "design_id":"44444444-4444-4444-4444-444444444444",
    // assert order.designId == that UUID; and absent key → nil (add one line
    // to testOrderDecodesWithoutEventDate: XCTAssertNil(order.designId)).
}

func testOrderLockDecodes() throws {
    let json = """
    {"id":"11111111-1111-1111-1111-111111111111",
     "boutique_id":"22222222-2222-2222-2222-222222222222",
     "order_id":"33333333-3333-3333-3333-333333333333",
     "design_id":null,"render_image_path":null,"fabric_code":"BNRS-EM-01",
     "fabric_description":"emerald banarasi","measurement_id":null,
     "price_breakup":{"fabric":40000,"work":50000,"other":10000},
     "event_date":"2026-09-19","alteration_buffer_days":7,
     "must_finish_by":"2026-09-09","advance_amount":50000,
     "rush_accepted":false,"locked_at":"2026-07-28T10:00:00Z"}
    """.data(using: .utf8)!
    let l = try orderDecoder().decode(OrderLock.self, from: json)
    XCTAssertEqual(l.fabricCode, "BNRS-EM-01")
    XCTAssertEqual(l.priceBreakup?.work, 50000)
    XCTAssertEqual(l.mustFinishBy, "2026-09-09")
}

func testChangeOrderDecodesWithNullEventDate() throws {
    let json = """
    {"id":"11111111-1111-1111-1111-111111111111",
     "boutique_id":"22222222-2222-2222-2222-222222222222",
     "order_id":"33333333-3333-3333-3333-333333333333",
     "description":"sleeves added","price_delta":1000,
     "new_event_date":null,"created_at":"2026-07-28T10:00:00Z"}
    """.data(using: .utf8)!
    let co = try orderDecoder().decode(ChangeOrder.self, from: json)
    XCTAssertEqual(co.priceDelta, 1000)
    XCTAssertNil(co.newEventDate)
}
```

(Fixture dates are non-fractional ISO to suit the test-local `orderDecoder()`;
production decoding goes through the Supabase SDK's fractional-tolerant
decoder — do NOT "fix" the test decoder.)

- [ ] **Step 2: Run — FAIL. Step 3: Implement.**
  - `Order`: add `var designId: UUID?` + CodingKey `design_id` + `designId = try c.decodeIfPresent(...)` in the custom init.
  - `OrderLock.swift`:

```swift
import Foundation

/// R3 — the frozen contract for an order. Immutable once written (no update
/// path in app or service); post-lock changes live in ChangeOrder rows.
struct PriceBreakup: Codable, Hashable {
    var fabric: Double
    var work: Double
    var other: Double
    var sum: Double { fabric + work + other }
}

struct OrderLock: Identifiable, Codable, Hashable {
    let id: UUID
    var boutiqueId: UUID
    var orderId: UUID
    var designId: UUID?
    var renderImagePath: String?
    var fabricCode: String?
    var fabricDescription: String?
    var measurementId: UUID?
    var priceBreakup: PriceBreakup?
    var eventDate: String?            // frozen copies — YYYY-MM-DD
    var alterationBufferDays: Int?
    var mustFinishBy: String?
    var advanceAmount: Double
    var rushAccepted: Bool
    var lockedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case boutiqueId = "boutique_id"
        case orderId = "order_id"
        case designId = "design_id"
        case renderImagePath = "render_image_path"
        case fabricCode = "fabric_code"
        case fabricDescription = "fabric_description"
        case measurementId = "measurement_id"
        case priceBreakup = "price_breakup"
        case eventDate = "event_date"
        case alterationBufferDays = "alteration_buffer_days"
        case mustFinishBy = "must_finish_by"
        case advanceAmount = "advance_amount"
        case rushAccepted = "rush_accepted"
        case lockedAt = "locked_at"
    }
}

/// jsonb payload for the lock_order RPC.
struct NewOrderLock: Encodable {
    let boutique_id: UUID
    let order_id: UUID
    let design_id: UUID?
    let render_image_path: String?
    let fabric_code: String?
    let fabric_description: String?
    let measurement_id: UUID?
    let price_breakup: PriceBreakup?
    let event_date: String?
    let alteration_buffer_days: Int?
    let must_finish_by: String?
    let advance_amount: Double
    let rush_accepted: Bool
}

struct ChangeOrder: Identifiable, Codable, Hashable {
    let id: UUID
    var boutiqueId: UUID
    var orderId: UUID
    var description: String
    var priceDelta: Double
    var newEventDate: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, description
        case boutiqueId = "boutique_id"
        case orderId = "order_id"
        case priceDelta = "price_delta"
        case newEventDate = "new_event_date"
        case createdAt = "created_at"
    }
}
```

- [ ] **Step 4: `xcodegen generate`, run — PASS. Step 5: Commit** `feat: Order.designId + OrderLock/ChangeOrder models`

### Task 3: LockGate (TDD)

**Files:**
- Create: `ipad/Boutique360/Utilities/LockGate.swift`
- Create: `ipad/Boutique360Tests/LockGateTests.swift`

- [ ] **Step 1: Failing tests** (today = 2026-07-28, gregorian cal, same helpers as OrderSlackTests):

```swift
import XCTest
@testable import Boutique360

final class LockGateTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func d(_ y: Int, _ m: Int, _ dd: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: dd))!
    }
    private var today: Date { d(2026, 7, 28) }

    private func blockers(advance: Double = 500, event: Date? = nil,
                          fulfillment: FulfillmentMethod? = .pickup,
                          buffer: Int = 7, rush: Bool = false,
                          breakup: (Double, Double, Double)? = nil,
                          subtotal: Double = 1000) -> [LockGate.Blocker] {
        LockGate.blockers(advancePaid: advance, eventDate: event,
                          fulfillment: fulfillment, alterationBufferDays: buffer,
                          rushAccepted: rush,
                          breakup: breakup.map { (fabric: $0.0, work: $0.1, other: $0.2) },
                          subtotal: subtotal, today: today, calendar: cal)
    }

    func testNoAdvanceBlocks() {
        XCTAssertEqual(blockers(advance: 0), [.noAdvance])
    }
    func testAdvancePassesCleanOrder() {
        XCTAssertTrue(blockers().isEmpty)
    }
    func testEventInsideBufferBlocksUnlessRush() {
        // event 8/1: mustFinishBy = 7/25 < today 7/28 → blocked
        let e = d(2026, 8, 1)
        let mf = OrderSlack.mustFinishBy(eventDate: e, fulfillment: .pickup,
                                         alterationBufferDays: 7, calendar: cal)!
        XCTAssertEqual(blockers(event: e), [.eventInsideBuffer(mustFinishBy: mf)])
        XCTAssertTrue(blockers(event: e, rush: true).isEmpty)
    }
    func testMustFinishByTodayPasses() {
        // event 8/4 pickup buffer 7 → mustFinishBy 7/28 == today → OK
        XCTAssertTrue(blockers(event: d(2026, 8, 4)).isEmpty)
    }
    func testBreakupMismatchBlocks() {
        XCTAssertEqual(blockers(breakup: (400, 500, 50)),
                       [.breakupMismatch(sum: 950, subtotal: 1000)])
    }
    func testBreakupExactAtPaisePasses() {
        XCTAssertTrue(blockers(breakup: (400, 500, 99.999999)).isEmpty)
    }
    func testNilBreakupSkipsCheck() {
        XCTAssertTrue(blockers(breakup: nil).isEmpty)
    }
    func testBlockerOrderAdvanceFirst() {
        let e = d(2026, 8, 1)
        let bs = blockers(advance: 0, event: e, breakup: (1, 1, 1))
        XCTAssertEqual(bs.first, .noAdvance)
        XCTAssertEqual(bs.count, 3)
    }
}
```

- [ ] **Step 2: Run — FAIL. Step 3: Implement** per spec Unit 3 (checks in order advance → event → breakup; `Money.equalAtPaise` for the breakup comparison; `OrderSlack.mustFinishBy` + `startOfDay` for the event rule). **Step 4: Run — 8 PASS. Step 5: Commit** `feat: LockGate pure lock-validation + 8 tests`

**Chunk 1 gate:** full suite green (expect 164 + ~11 new).

---

## Chunk 2: Service + UI + docs

### Task 4: OrderLocksService

**Files:**
- Create: `ipad/Boutique360/Services/OrderLocksService.swift`

- [ ] **Step 1: Implement** (RPC wrappers; boutique-scoped reads):

```swift
import Foundation
import Supabase

/// R3 — the frozen contract + its change-order ledger. Lock inserts go
/// through the lock_order RPC (atomic with orders.design_id patch); COs
/// through apply_change_order (atomic totals/event update, server-enforced
/// lock precondition + subtotal floor).
enum OrderLocksService {
    static func get(orderId: UUID, boutiqueId: UUID) async throws -> OrderLock? {
        let rows: [OrderLock] = try await SupabaseService.client.from("order_locks")
            .select()
            .eq("boutique_id", value: boutiqueId)
            .eq("order_id", value: orderId)
            .limit(1)
            .execute().value
        return rows.first
    }

    static func lock(_ input: NewOrderLock) async throws -> OrderLock {
        struct P: Encodable { let p_lock: NewOrderLock }
        return try await SupabaseService.client
            .rpc("lock_order", params: P(p_lock: input))
            .execute().value
    }

    static func changeOrders(orderId: UUID, boutiqueId: UUID) async throws -> [ChangeOrder] {
        try await SupabaseService.client.from("change_orders")
            .select()
            .eq("boutique_id", value: boutiqueId)
            .eq("order_id", value: orderId)
            .order("created_at", ascending: false)
            .execute().value
    }

    static func applyChangeOrder(orderId: UUID, description: String,
                                 priceDelta: Double, newEventDate: String?) async throws -> ChangeOrder {
        struct P: Encodable {
            let p_order_id: UUID
            let p_description: String
            let p_price_delta: Double
            let p_new_event_date: String?
        }
        return try await SupabaseService.client
            .rpc("apply_change_order",
                 params: P(p_order_id: orderId, p_description: description,
                           p_price_delta: priceDelta, p_new_event_date: newEventDate))
            .execute().value
    }
}
```

- [ ] **Step 2: `xcodegen generate` + build green. Step 3: Commit** `feat: OrderLocksService (lock_order + apply_change_order wrappers)`

### Task 5: LockSheet

**Files:**
- Create: `ipad/Boutique360/Features/Orders/LockSheet.swift`

Structure (spec Unit 5; Form-based like VirtualTryOnView):
- Init: `LockSheet(order: Order, customer: Customer?, onLocked: (OrderLock) -> Void)`.
- `.task`: parallel best-effort loads — designs (`DesignsService.list(customerId: order.customerId)`), measurements (`MeasurementsService.listForCustomer(order.customerId)`, default selection = most recent by `takenAt`), advance (`PaymentsService.capturedSumsForOrders([order.id])` → sum; **an empty result array means ₹0 advance — map to `0.0`, not nil**; nil is reserved for loading/thrown-error), and on design pick: renders (`DesignRendersService.listForDesign(id)` → first `status == .done`, show via `StorageService.signedURL(bucket: .designRenders, path:)`).
- State: `selectedDesignId: UUID?`, `renderPath: String?`, `fabricCode: String`, `fabricDescription: String`, `selectedMeasurementId: UUID?`, `useBreakup: Bool` + three text fields (String mirrors → Double, same pattern as PaymentsSectionView's amountText), `rushAccepted: Bool`, `advancePaid: Double?` (nil = still loading/failed), `locking: Bool`, `error: String?`.
- Sections: Design (picker + render thumbnail) · Fabric (code + description) · Measurements (picker labeled "\(garmentType) — \(takenAt.formatted(date:.abbreviated,…))", "None" allowed) · Price breakup (toggle; three fields + live sum check line vs `order.subtotal`) · Event plan (read-only: event date, buffer, `OrderSlack.mustFinishBy`, `SlackBadge`; red warning + rush toggle when mustFinishBy < today) · Advance (`Formatters.inr(advancePaid ?? 0)` or "couldn't load — retry") · Lock button.
- Lock button `.disabled` while `locking || advancePaid == nil || !LockGate.blockers(...).isEmpty`; first blocker's human message shown beneath:
  - `.noAdvance` → "Record an advance payment first — no advance, no lock."
  - `.eventInsideBuffer(d)` → "Must finish by \(d, abbreviated) is already past. Accept rush to lock anyway."
  - `.breakupMismatch(s, t)` → "Breakup sums to \(inr(s)), order subtotal is \(inr(t))."
- Lock action: build `NewOrderLock` (must_finish_by via `OrderSlack.mustFinishBy` formatted `Formatters.postgresDate`; event/buffer copied from order) → `OrderLocksService.lock`. On error containing "23505"/duplicate: re-`get` and call `onLocked(existing)` (treat as success). Other errors → inline.

- [ ] **Step 1: Implement. Step 2: build green. Step 3: Commit** `feat: LockSheet — freeze the look (design, fabric, naap pin, breakup, rush, advance gate)`

### Task 6: OrderDetailView integration + LockSummarySheet

**Files:**
- Modify: `ipad/Boutique360/Features/Orders/OrderDetailView.swift`
- Create: `ipad/Boutique360/Features/Orders/LockSummarySheet.swift`

- [ ] **Step 1: OrderDetailView.** State: `@State private var lock: OrderLock?`, `@State private var lockLoadFailed = false`, `@State private var showLockSheet = false`, `@State private var showLockSummary = false`. In `loadItems()`: `do { lock = try await OrderLocksService.get(orderId: order.id, boutiqueId: bid); lockLoadFailed = false } catch { lockLoadFailed = true }` (never offer locking on unknown state). Summary section additions:

```swift
if let lock {
    LabeledContent("Locked") {
        Button { showLockSummary = true } label: {
            Label(lock.lockedAt.formatted(date: .abbreviated, time: .omitted),
                  systemImage: "lock.fill")
        }
    }
} else if !lockLoadFailed, [.pending, .confirmed].contains(current.status) {
    Button { showLockSheet = true } label: {
        Label("Lock the look", systemImage: "lock")
    }
}
```

The R1 "Event deadline" row stays; when `lock != nil` add caption "Changes via change order only." Sheets: `.sheet(isPresented: $showLockSheet) { NavigationStack { LockSheet(order: current, customer: customer) { l in lock = l; showLockSheet = false } } }` and `.sheet(isPresented: $showLockSummary) { NavigationStack { LockSummarySheet(order: current, lock: lock!) { NotificationCenter.default.post(name: .orderDidChange, object: nil) } } }` — guard the force-unwrap with `if let`.

- [ ] **Step 2: LockSummarySheet.** Init `(order: Order, lock: OrderLock, onChanged: () -> Void)`. Sections: The contract (render thumbnail via signed URL when `renderImagePath != nil` · fabric code/description · pinned measurement — fetch `MeasurementsService.listForCustomer` and find by `measurementId`, show garmentType + takenAt, or "not pinned" · breakup rows + frozen note "agreed at lock; later changes live in the ledger below" · frozen event plan (event/buffer/mustFinishBy) · advance + rush flag) · Change orders (list from `OrderLocksService.changeOrders`, newest first: description, signed ±`Formatters.inr`, optional "event → \(date)", timestamp; empty state "No changes since lock") · Add change order (description TextField, delta String-mirror field allowing negative, optional event DatePicker behind a toggle; Apply button `.disabled(description.isEmpty)` → `applyChangeOrder`; on success refresh list + call `onChanged()`; errors inline — the RPC's exception messages are user-meaningful).

- [ ] **Step 3:** `xcodegen generate` + FULL test suite + build — green. Manual: lock an order in the simulator (record a payment first), verify the deadline row goes read-only, apply a CO with +₹1000 and a new date, verify totals + badge recompute.

- [ ] **Step 4: Commit** `feat: R3 lock + change-orders wired into OrderDetailView`

### Task 7: Docs + push

- [ ] **Step 1:** `docs/app-map.md` (§2 Orders rows for lock/CO; §5 no change; §7 R3 → ✅ SHIPPED), `docs/api-rpcs.md` (lock_order + apply_change_order contracts incl. server-side gates), `README.md` (R3 ✅, test count), `CHANGELOG.md` (R3 entry), `CLAUDE.md` (speed-dial: `LockGate.swift`, `OrderLocksService.swift`; migration count 29; test count).
- [ ] **Step 2:** Full suite — expect ~175, 0 failures.
- [ ] **Step 3: Commit** `docs: R3 lock screen shipped` **and push** `git push origin main:boutique-360-ipad-app`.
