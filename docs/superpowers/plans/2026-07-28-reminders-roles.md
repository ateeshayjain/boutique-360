# Reminders (R4a) + PIN-scoped Roles (R4b) Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-drafted WhatsApp reminders with one-tap approve (R4a), and owner/assistant role separation gated by a hashed PIN with device-auth recovery (R4b), plus the compliance deliverables the standards checklists require.

**Architecture:** Two independent subsystems. **Chunk A (R4a)** adds `reminder_log` + a pure `ReminderDrafts` engine fed entirely by data the Dashboard already loads, rendered inside `MorningBoardView`. **Chunk B (R4b)** adds pure `PinPolicy`/`RolePolicy`, hardens `KeychainStore`, and introduces `StaffRoleContext` which gates ten money surfaces. **Chunk C** is documentation only. A ships and works without B (no assistant mode ⇒ every user is owner ⇒ ungated drafts are correct); B then gates A's payment drafts.

**Tech Stack:** Swift/SwiftUI iOS 17, CryptoKit + LocalAuthentication (system frameworks — no new dependencies), XCTest pure-logic-only, Supabase Postgres (migrations via MCP).

**Spec:** `docs/superpowers/specs/2026-07-28-reminders-roles-design.md` — **read it first.** Its rules are normative: the degraded-input suppression table, the `forDate` semantics table, the "no un-gated draft may contain a rupee amount" rule, and the `LockState` three-way split are not negotiable simplifications.

**Conventions (CLAUDE.md):** stateless `enum` services with `static func … async throws`; boutique-scoped queries also pass `.eq("boutique_id", value: bid)`; `Formatters.postgresDate` for DATE strings, `Formatters.inr` for money; `Money.roundedToPaise`/`equalAtPaise` for currency comparison; never `print()`; after adding any `.swift` run `cd ipad && xcodegen generate`; commit per task with trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Push once at the end of each chunk to `origin main:boutique-360-ipad-app` (remote `main` holds an unrelated stub — never force-push it).

**Build/test:**
```bash
cd ipad && xcodegen generate && xcodebuild -project Boutique360.xcodeproj -scheme Boutique360 \
  -destination 'platform=iOS Simulator,id=092B3063-9443-4E76-AD24-3918E9A0695C' test -only-testing:Boutique360Tests/<Suite>
```
Full suite: drop the `-only-testing` flag. Baseline before this plan: **175 tests, 0 failures.**

---

## Chunk A: R4a — auto-drafted reminders

### Task A1: Migration 0030 + RLS round-trip verification

**Files:**
- Create: `supabase/migrations/0030_reminder_log.sql`

- [ ] **Step 1: Write the migration** (spec Unit 1, verbatim):

```sql
-- 0030 — R4a reminder dedup log. Append-only: a handled reminder stays handled.
create table if not exists public.reminder_log (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  kind text not null check (kind in ('fitting','payment','ready')),
  subject_id uuid not null,          -- appointment id (fitting) | order id (payment/ready)
  for_date date not null,
  created_at timestamptz not null default now(),
  unique (boutique_id, kind, subject_id, for_date)
);
create index if not exists reminder_log_boutique_date_idx
  on public.reminder_log(boutique_id, for_date);
alter table public.reminder_log enable row level security;
-- Append-only for the app (same shape as change_orders in 0029): select +
-- insert only. No update/delete policy → RLS denies them.
create policy "reminder_log_select" on public.reminder_log for select to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "reminder_log_insert" on public.reminder_log for insert to authenticated
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "reminder_log_service" on public.reminder_log for all to service_role
  using (true) with check (true);
```

- [ ] **Step 2: Apply** via Supabase MCP `apply_migration` (project `tdnwdlrkbrtoxjzcgusg`, name `reminder_log`). If MCP permission is denied, STOP and surface to the human — do not work around.

- [ ] **Step 3: SQL-level smoke** via MCP `execute_sql` — a rollback-wrapped `DO` block (NOT CTEs; unreferenced SELECT CTEs never execute):

```sql
begin;
do $$
declare v_bid uuid; v_n int;
begin
  select id into v_bid from public.boutiques limit 1;
  insert into public.reminder_log (boutique_id, kind, subject_id, for_date)
  values (v_bid, 'payment', gen_random_uuid(), current_date);
  select count(*) into v_n from public.reminder_log where boutique_id = v_bid;
  assert v_n >= 1, 'insert failed';
  raise notice 'reminder_log insert OK';
end $$;
rollback;
```

- [ ] **Step 4: VERIFICATION TASK — client-level RLS probe. DO THIS NOW, before writing any Swift.** *(Reviewer-flagged: verification task with its own pass criteria — must not be waved through. Moved ahead of the engine work: `current_setting('app.boutique_id', true)` is transaction-local and there is **no client call site** for `set_boutique_id_from_user()` anywhere in `ipad/Boutique360/`, so there is a material chance the anon/authenticated role sees nothing. Discovering that after building a 21-test engine wastes the engine.)*

  **It must be an INSERT probe, not a read.** Under RLS a `select` with no
  matching policy returns **200 with `[]`** — indistinguishable from "the
  table is simply empty," so a read probe passes in exactly the failure case
  it exists to catch. An insert whose `with check` fails returns **403
  `new row violates row-level security policy`**, which discriminates.

  ```bash
  cd /Users/ateeshayjain/WIPApps/boutique-360
  ANON=$(grep SUPABASE_ANON_KEY ipad/Boutique360/Configuration/Env.xcconfig | sed 's/.*= *//')
  URL="https://tdnwdlrkbrtoxjzcgusg.supabase.co/rest/v1/reminder_log"
  BID=$(curl -s "https://tdnwdlrkbrtoxjzcgusg.supabase.co/rest/v1/boutiques?select=id&limit=1" \
        -H "apikey: $ANON" -H "Authorization: Bearer $ANON" | python3 -c 'import sys,json; print(json.load(sys.stdin)[0]["id"])')
  curl -s -w "\nHTTP %{http_code}\n" -X POST "$URL" \
    -H "apikey: $ANON" -H "Authorization: Bearer $ANON" \
    -H "Content-Type: application/json" -H "Prefer: return=representation" \
    -d "{\"boutique_id\":\"$BID\",\"kind\":\"payment\",\"subject_id\":\"$(uuidgen | tr 'A-Z' 'a-z')\",\"for_date\":\"$(date +%F)\"}"
  ```

  **Pass criteria:** HTTP **201** and a returned row. Then delete the probe
  row via MCP `execute_sql`.

  **On 403 (`violates row-level security policy`): STOP.** Do not add a
  service-role workaround, do not proceed to A2. Report to the human with
  the exact response body — this is a project-wide RLS/session question (it
  would affect every shipped boutique-scoped table equally), not an R4a
  question.

  Note the probe runs as role `anon`, while the policies target
  `authenticated` — so a 403 here may reflect the probe's role rather than a
  real app failure. That is why Task A3 Step 3 re-runs the round-trip
  **through the app's own authenticated session**, which is the definitive
  gate. This step is the cheap early signal; A3 Step 3 is the proof.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0030_reminder_log.sql
git commit -m "feat: migration 0030 — reminder_log (append-only dedup)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task A2: `ReminderDrafts` pure engine (TDD)

**Files:**
- Create: `ipad/Boutique360/Utilities/ReminderDrafts.swift`
- Create: `ipad/Boutique360Tests/ReminderDraftsTests.swift`

- [ ] **Step 1: Write the failing test suite.** Fixtures via JSON decode (models have no public inits — same technique as `MorningBoardTests`). Copy that file's helper style.

```swift
import XCTest
@testable import Boutique360

/// R4a — spec Unit 2 rules. today = 2026-07-28 throughout.
final class ReminderDraftsTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func d(_ y: Int, _ m: Int, _ dd: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: dd))!
    }
    private var today: Date { d(2026, 7, 28) }
    private let dec: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
    private let bid = "22222222-2222-2222-2222-222222222222"

    private func customer(consent: Bool = true, phone: String? = "9876543210",
                          id: UUID = UUID()) -> Customer {
        let phoneLine = phone.map { "\"phone\":\"\($0)\"," } ?? ""
        return try! dec.decode(Customer.self, from: """
        {"id":"\(id.uuidString)","boutique_id":"\(bid)","name":"Priya Mehta",
         \(phoneLine)"tags":[],"vip_status":false,"loyalty_points":0,
         "source":"walkin","consent_whatsapp":\(consent),"consent_email":false,
         "created_at":"2026-07-01T10:00:00Z","updated_at":"2026-07-01T10:00:00Z"}
        """.data(using: .utf8)!)
    }

    private func appointment(customerId: UUID, type: String = "fitting",
                             status: String = "scheduled",
                             at: Date, id: UUID = UUID()) -> Appointment {
        let iso = ISO8601DateFormatter()
        return try! dec.decode(Appointment.self, from: """
        {"id":"\(id.uuidString)","boutique_id":"\(bid)","customer_id":"\(customerId.uuidString)",
         "type":"\(type)","scheduled_at":"\(iso.string(from: at))","duration_minutes":30,
         "status":"\(status)","created_at":"2026-07-01T10:00:00Z","updated_at":"2026-07-01T10:00:00Z"}
        """.data(using: .utf8)!)
    }

    private func order(_ num: String, customerId: UUID, status: String = "confirmed",
                       total: Double = 1000, placed: String = "2026-07-01T10:00:00Z",
                       id: UUID = UUID()) -> Order {
        try! dec.decode(Order.self, from: """
        {"id":"\(id.uuidString)","boutique_id":"\(bid)","order_number":"\(num)",
         "customer_id":"\(customerId.uuidString)","status":"\(status)","subtotal":\(total),
         "gst_amount":0,"total":\(total),"currency":"INR","placed_at":"\(placed)",
         "created_at":"\(placed)","updated_at":"\(placed)"}
        """.data(using: .utf8)!)
    }

    private func card(orderId: UUID, status: String = "ready", id: UUID = UUID()) -> JobCard {
        try! dec.decode(JobCard.self, from: """
        {"id":"\(id.uuidString)","boutique_id":"\(bid)","job_number":"JC-1",
         "order_id":"\(orderId.uuidString)","status":"\(status)","fabric_list_json":[],
         "current_stage":0,"stages_progress_json":[],
         "created_at":"2026-07-01T10:00:00Z","updated_at":"2026-07-01T10:00:00Z"}
        """.data(using: .utf8)!)
    }

    private func build(appointments: [Appointment] = [], orders: [Order] = [],
                       cards: [UUID: JobCard] = [:], events: [UUID: JobCardEvent] = [:],
                       received: [UUID: Double] = [:], customers: [UUID: Customer] = [:],
                       logged: Set<String> = [], failed: Set<MorningBoard.Input> = [])
                       -> [ReminderDrafts.Draft] {
        ReminderDrafts.build(appointments: appointments, orders: orders,
                             jobCardsByOrder: cards, latestEventByCard: events,
                             receivedByOrder: received, customersById: customers,
                             logged: logged, failedInputs: failed,
                             boutiqueName: "Aangan", today: today, calendar: cal)
    }

    // ── Fitting rule
    func testFittingTodayAndTomorrowIncluded() {
        let c = customer()
        let a1 = appointment(customerId: c.id, at: d(2026, 7, 28))
        let a2 = appointment(customerId: c.id, at: d(2026, 7, 29))
        let drafts = build(appointments: [a1, a2], customers: [c.id: c])
        XCTAssertEqual(drafts.count, 2)
        XCTAssertTrue(drafts.allSatisfy { $0.kind == .fitting })
        // forDate is the APPOINTMENT's date, not today
        XCTAssertEqual(Set(drafts.map(\.forDate)), ["2026-07-28", "2026-07-29"])
    }
    func testFittingDayAfterTomorrowExcluded() {
        let c = customer()
        let a = appointment(customerId: c.id, at: d(2026, 7, 30))
        XCTAssertTrue(build(appointments: [a], customers: [c.id: c]).isEmpty)
    }
    func testNonFittingTypeExcluded() {
        let c = customer()
        let a = appointment(customerId: c.id, type: "consultation", at: d(2026, 7, 28))
        XCTAssertTrue(build(appointments: [a], customers: [c.id: c]).isEmpty)
    }
    func testCancelledAppointmentExcluded() {
        let c = customer()
        let a = appointment(customerId: c.id, status: "cancelled", at: d(2026, 7, 28))
        XCTAssertTrue(build(appointments: [a], customers: [c.id: c]).isEmpty)
    }

    // ── Payment rule
    func testPaymentIncludedAtExactlySevenDays() {
        let c = customer()
        // placed 7/21 → exactly 7 days before 7/28
        let o = order("BQ-1", customerId: c.id, placed: "2026-07-21T10:00:00Z")
        let drafts = build(orders: [o], received: [o.id: 400], customers: [c.id: c])
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].kind, .payment)
        XCTAssertEqual(drafts[0].amountDue, 600)
        XCTAssertEqual(drafts[0].forDate, "2026-07-28")   // payment forDate = today
    }
    func testPaymentExcludedAtSixDays() {
        let c = customer()
        let o = order("BQ-1", customerId: c.id, placed: "2026-07-22T10:00:00Z")
        XCTAssertTrue(build(orders: [o], customers: [c.id: c]).isEmpty)
    }
    func testPaymentExcludesPendingStatus() {
        // Matches DashboardView.filterOverdue exactly.
        let c = customer()
        let o = order("BQ-1", customerId: c.id, status: "pending")
        XCTAssertTrue(build(orders: [o], customers: [c.id: c]).isEmpty)
    }
    func testFullyPaidExcluded() {
        let c = customer()
        let o = order("BQ-1", customerId: c.id, total: 1000)
        XCTAssertTrue(build(orders: [o], received: [o.id: 1000], customers: [c.id: c]).isEmpty)
    }

    // ── Ready rule
    func testReadyIncludedFromCardStatus() {
        let c = customer()
        let o = order("BQ-1", customerId: c.id, status: "confirmed")
        let jc = card(orderId: o.id, status: "ready")
        let drafts = build(orders: [o], cards: [o.id: jc],
                           received: [o.id: 1000], customers: [c.id: c])
        XCTAssertEqual(drafts.map(\.kind), [.ready])
    }
    func testReadyExcludedWhenDelivered() {
        let c = customer()
        let o = order("BQ-1", customerId: c.id, status: "delivered")
        let jc = card(orderId: o.id, status: "ready")
        XCTAssertTrue(build(orders: [o], cards: [o.id: jc],
                            received: [o.id: 1000], customers: [c.id: c]).isEmpty)
    }

    // ── Consent gate (DPDP)
    func testNoConsentProducesNoDraft() {
        let c = customer(consent: false)
        let a = appointment(customerId: c.id, at: d(2026, 7, 28))
        XCTAssertTrue(build(appointments: [a], customers: [c.id: c]).isEmpty)
    }
    func testNoPhoneProducesNoDraft() {
        let c = customer(phone: nil)
        let a = appointment(customerId: c.id, at: d(2026, 7, 28))
        XCTAssertTrue(build(appointments: [a], customers: [c.id: c]).isEmpty)
    }

    // ── Dedup
    func testLoggedKeyExcludesDraft() {
        let c = customer()
        let a = appointment(customerId: c.id, at: d(2026, 7, 28))
        let key = ReminderDrafts.key(kind: .fitting, subjectId: a.id, forDate: "2026-07-28")
        XCTAssertTrue(build(appointments: [a], customers: [c.id: c], logged: [key]).isEmpty)
    }
    func testKeyIsLowercasedAndStable() {
        let id = UUID()
        let k = ReminderDrafts.key(kind: .payment, subjectId: id, forDate: "2026-07-28")
        XCTAssertEqual(k, "payment-\(id.uuidString.lowercased())-2026-07-28")
        XCTAssertFalse(k.contains(where: { $0.isUppercase }))
    }

    // ── Degraded inputs (the correctness rule, not cosmetics)
    func testPaymentsFailureSuppressesPaymentDrafts() {
        // Without this, an empty receivedByOrder makes every balance look
        // like the full total — nudging customers for money already paid.
        let c = customer()
        let o = order("BQ-1", customerId: c.id, placed: "2026-07-01T10:00:00Z")
        let drafts = build(orders: [o], received: [:], customers: [c.id: c],
                           failed: [.payments])
        XCTAssertTrue(drafts.filter { $0.kind == .payment }.isEmpty)
    }
    func testOrdersFailureSuppressesPaymentAndReady() {
        let c = customer()
        let o = order("BQ-1", customerId: c.id, placed: "2026-07-01T10:00:00Z")
        let jc = card(orderId: o.id)
        let drafts = build(orders: [o], cards: [o.id: jc], received: [o.id: 0],
                           customers: [c.id: c], failed: [.orders])
        XCTAssertTrue(drafts.filter { $0.kind == .payment || $0.kind == .ready }.isEmpty)
    }
    func testJobCardsFailureSuppressesReady() {
        let c = customer()
        let o = order("BQ-1", customerId: c.id)
        let jc = card(orderId: o.id)
        let drafts = build(orders: [o], cards: [o.id: jc], received: [o.id: 1000],
                           customers: [c.id: c], failed: [.jobCards])
        XCTAssertTrue(drafts.filter { $0.kind == .ready }.isEmpty)
    }
    func testEventsFailureSuppressesReady() {
        // The done-signal also comes from karigar events; if those failed we
        // don't know whether the piece is ready. Better silent than wrong.
        let c = customer()
        let o = order("BQ-1", customerId: c.id)
        let jc = card(orderId: o.id)
        let drafts = build(orders: [o], cards: [o.id: jc], received: [o.id: 1000],
                           customers: [c.id: c], failed: [.events])
        XCTAssertTrue(drafts.filter { $0.kind == .ready }.isEmpty)
    }
    func testAppointmentsFailureSuppressesFitting() {
        let c = customer()
        let a = appointment(customerId: c.id, at: d(2026, 7, 28))
        XCTAssertTrue(build(appointments: [a], customers: [c.id: c],
                            failed: [.appointments]).isEmpty)
    }

    // ── Security rule: no un-gated draft carries money
    func testOnlyPaymentDraftsContainRupeeAmounts() {
        // Mixed case on purpose: oReady is fully paid (→ ready draft only),
        // oPay is old and unpaid (→ payment draft). Without oPay the loop
        // would never see the kind the rule is actually about.
        let c = customer()
        let a = appointment(customerId: c.id, at: d(2026, 7, 28))
        let oReady = order("BQ-R", customerId: c.id)
        let jc = card(orderId: oReady.id, status: "ready")
        let oPay = order("BQ-P", customerId: c.id, placed: "2026-07-01T10:00:00Z")
        let drafts = build(appointments: [a], orders: [oReady, oPay],
                           cards: [oReady.id: jc],
                           received: [oReady.id: 1000, oPay.id: 0],
                           customers: [c.id: c])
        XCTAssertTrue(drafts.contains { $0.kind == .payment }, "need a payment draft in the mix")
        for draft in drafts where draft.kind != .payment {
            XCTAssertFalse(draft.message.contains("₹"),
                           "\(draft.kind) message must not contain money — it renders un-gated")
            XCTAssertNil(draft.amountDue)
        }
    }

    // ── Sort + determinism
    func testSortOrderFittingReadyPayment() {
        let c = customer()
        let a = appointment(customerId: c.id, at: d(2026, 7, 28))
        let oReady = order("BQ-R", customerId: c.id)
        let jc = card(orderId: oReady.id, status: "ready")
        let oPay = order("BQ-P", customerId: c.id, placed: "2026-07-01T10:00:00Z")
        let drafts = build(appointments: [a], orders: [oPay, oReady],
                           cards: [oReady.id: jc],
                           received: [oReady.id: 1000, oPay.id: 0],
                           customers: [c.id: c])
        XCTAssertEqual(drafts.map(\.kind), [.fitting, .ready, .payment])
    }

    func testEmptyInputsProduceNoDrafts() {
        XCTAssertTrue(build().isEmpty)
    }
}
```

- [ ] **Step 2: `cd ipad && xcodegen generate`, run the suite** — expect FAIL (`ReminderDrafts` undefined).

- [ ] **Step 3: Implement** `ipad/Boutique360/Utilities/ReminderDrafts.swift` per spec Unit 2. The spec's rule tables are normative — transcribe, don't re-derive. Structure:

```swift
import Foundation

/// R4a — pure draft builder for the Dashboard's Reminders section.
/// Rules (inclusion, forDate semantics, degraded-input suppression, sort)
/// are specified in docs/superpowers/specs/2026-07-28-reminders-roles-design.md
/// Unit 2 and are normative.
enum ReminderDrafts {
    enum Kind: String, Equatable, CaseIterable { case fitting, payment, ready }

    struct Draft: Equatable, Identifiable { /* per spec */ }

    /// THE single key format — both this file and RemindersService MUST call
    /// it. Swift's uuidString is uppercase, Postgres returns lowercase;
    /// lowercasing here is what keeps dedup working.
    static func key(kind: Kind, subjectId: UUID, forDate: String) -> String {
        "\(kind.rawValue)-\(subjectId.uuidString.lowercased())-\(forDate)"
    }

    static func build(...) -> [Draft] { ... }
}
```

Implementation notes binding the spec:
- Apply `failedInputs` suppressions **first**, before any other rule.
- Consent gate: `consentWhatsapp == true && whatsappTarget != nil` ⇒ otherwise no draft (not a disabled row). `Draft.whatsappTarget` is non-optional.
- `forDate`: fitting → the appointment's date via `Formatters.postgresDate`; payment/ready → today.
- Payment: status ∉ {pending, cancelled, returned}; `Money.roundedToPaise(total − received) > 0`; `(placedAt ?? createdAt)` at least 7 days before today (compare via `calendar.dateComponents([.day], …)` on `startOfDay`).
- Ready: done-signal = card status `.ready`/`.delivered` OR latest event `.ready`; order status ∉ {delivered, cancelled, returned}.
- Suppressions (spec's degraded table — **all five**): `.payments` → no payment; `.orders` → no payment, no ready; `.jobCards` → no ready; **`.events` → no ready**; `.appointments` → no fitting.
- Copy — the three exact strings (money via `Formatters.inr`, and only in the payment one):
  - payment (verbatim `PaymentsSectionView.swift:90`):
    `"Hi \(first), a gentle reminder — balance of \(Formatters.inr(due)) is pending on order \(orderNo). UPI / card / cash all accepted. Thank you! — \(boutique)"`
  - ready (`CustomerNotifier.orderReadyPlan` **minus its `Total:` clause** — that clause is why it's not verbatim):
    `"Hi \(first), your order \(orderNo) from \(boutique) is ready! Drop by or reply for delivery."`
  - fitting (new):
    `"Namaste \(first)! Reminder — aapki fitting \(day) ko \(time) baje hai. — \(boutique)"`
    where `day` is the appointment date (`.dateTime.weekday(.wide).day().month()`) and `time` is `.dateTime.hour().minute()`.
- Sort: fitting (earliest `scheduledAt`) → ready → payment (largest balance); ties by `customerName`, then `subjectId.uuidString`.

- [ ] **Step 4: Run the suite** — expect all **22** PASS (suite total 175 + 22 = **197**).

- [ ] **Step 5: Commit** `feat: ReminderDrafts pure engine + 22 tests`

### Task A3: `RemindersService`

**Files:**
- Create: `ipad/Boutique360/Services/RemindersService.swift`

- [ ] **Step 1: Implement:**

```swift
import Foundation
import Supabase

/// R4a — the dedup ledger. Append-only at the DB (0030 has select+insert
/// policies only), so a handled reminder stays handled.
enum RemindersService {
    private struct Row: Decodable {
        let kind: String
        let subject_id: UUID
        let for_date: String
    }

    /// Keys for the window the drafts cover (today → tomorrow).
    /// Builds keys via ReminderDrafts.key so both sides share one format.
    static func loggedKeys(boutiqueId: UUID, from: String, to: String) async throws -> Set<String> {
        let rows: [Row] = try await SupabaseService.client.from("reminder_log")
            .select("kind,subject_id,for_date")
            .eq("boutique_id", value: boutiqueId)
            .gte("for_date", value: from)
            .lte("for_date", value: to)
            .execute().value
        return Set(rows.compactMap { row in
            ReminderDrafts.Kind(rawValue: row.kind).map {
                ReminderDrafts.key(kind: $0, subjectId: row.subject_id, forDate: row.for_date)
            }
        })
    }

    /// Idempotent: the unique constraint makes a double-tap a 23505, which
    /// means "already handled" — success, not failure.
    static func markDone(boutiqueId: UUID, kind: ReminderDrafts.Kind,
                         subjectId: UUID, forDate: String) async throws {
        struct NewRow: Encodable {
            let boutique_id: UUID
            let kind: String
            let subject_id: UUID
            let for_date: String
        }
        do {
            _ = try await SupabaseService.client.from("reminder_log")
                .insert(NewRow(boutique_id: boutiqueId, kind: kind.rawValue,
                               subject_id: subjectId, for_date: forDate))
                .execute()
        } catch let error as PostgrestError {
            // Prefer the typed code; fall back to the message only if the
            // SDK didn't populate it. String-sniffing alone is fragile.
            let isDuplicate = error.code == "23505"
                || error.message.lowercased().contains("duplicate key")
            guard isDuplicate else { throw error }
            // Already logged — that IS the desired end state.
        }
    }
}
```

- [ ] **Step 2: `xcodegen generate` + build** — green.

- [ ] **Step 3: VERIFICATION TASK — app-session RLS round-trip. This is the definitive gate** (A1 Step 4 was the cheap early signal; this runs through the app's own authenticated session, which is what actually ships).

  Procedure — add a temporary `#if DEBUG` probe (a button in `SettingsView`, or a one-shot call in `DashboardView.task`), run it in the simulator signed in as the demo user, and:
  1. Call `RemindersService.markDone(boutiqueId: bid, kind: .payment, subjectId: <fresh UUID>, forDate: <today>)`.
  2. Call `RemindersService.loggedKeys(boutiqueId: bid, from: <today>, to: <today>)`.
  3. Confirm the key from step 1 is present in the returned set.

  **Pass criteria:** the key comes back. **If `loggedKeys` returns empty, or the insert throws an RLS error — STOP.** Do not add a service-role workaround, do not switch the policy to `anon`, do not proceed to A4. Report to the human with the exact error: every shipped boutique-scoped table uses this same policy shape, so a failure here is a project-wide finding, not an R4a one.

  Remove the temporary probe before committing. Record the result (pass/fail + the observed key) in this task's commit message alongside the A1 Step 4 result.

- [ ] **Step 4: Commit** `feat: RemindersService (append-only dedup ledger)` — include the RLS verification result in the commit body.

### Task A4: Dashboard wiring + Reminders UI

**Files:**
- Create: `ipad/Boutique360/Features/Dashboard/RemindersSectionView.swift`
- Modify: `ipad/Boutique360/Features/Dashboard/MorningBoardView.swift` (body between needs-you list and pipeline strip, ~lines 14–16)
- Modify: `ipad/Boutique360/Features/Dashboard/DashboardView.swift` (state block ~lines 6–24; `load()` ~line 290)

- [ ] **Step 1: `DashboardView` — add drafts state and build them in `load()`.**

Add one state property (the three maps `jobCardsByOrder` / `latestEventByCard` / `receivedByOrder` stay **function locals** — they're still in scope where the new block goes, nothing re-reads them across renders, and promoting them to `@State` would mean rewriting three assignment sites for no gain):

```swift
@State private var reminderDrafts: [ReminderDrafts.Draft] = []
```

(The existing `@State private var loading` already tracks `load()` being in
flight — pass it through as `remindersLoading`; no second flag needed.)

**Insertion point — this matters:** put the block **immediately before `self.loadFailed = anyFailed`** (currently `DashboardView.swift:426`). Placed after it, a failed log fetch would never reach the stale-data banner, breaking the spec's "log-fetch failure → section hidden **+ stale banner**" rule.

```swift
// R4a: one new query (the dedup log). Caller's contract — if it fails we
// build NO drafts, because without dedup the owner re-sends.
let todayKey = Formatters.postgresDate.string(from: now)
let tomorrowKey = Formatters.postgresDate.string(
    from: cal.date(byAdding: .day, value: 1, to: todayStart) ?? now)
if let bid {
    do {
        let logged = try await RemindersService.loggedKeys(
            boutiqueId: bid, from: todayKey, to: tomorrowKey)
        reminderDrafts = ReminderDrafts.build(
            appointments: weekAppts, orders: activeOrders,
            jobCardsByOrder: jobCardsByOrder, latestEventByCard: latestEventByCard,
            receivedByOrder: receivedByOrder, customersById: self.customers,
            logged: logged, failedInputs: failures,
            boutiqueName: self.boutique?.name ?? "Boutique", today: now)
    } catch {
        reminderDrafts = []      // no dedup ⇒ no drafts
        anyFailed = true
    }
} else {
    reminderDrafts = []
}
```

- [ ] **Step 2: `MorningBoardView`** — add parameters and render the section between the needs-you list and the pipeline strip:

```swift
let drafts: [ReminderDrafts.Draft]
let remindersLoading: Bool
let onSend: (ReminderDrafts.Draft) -> Void
let onMarkDone: (ReminderDrafts.Draft) -> Void
```

In `body`, between `needsYouList` and `pipelineStrip`:
```swift
RemindersSectionView(drafts: drafts, isLoading: remindersLoading,
                     onSend: onSend, onMarkDone: onMarkDone)
```
**Not** wrapped in `if !drafts.isEmpty` — the section owns its own loading and
empty states (spec Unit 7 requires both), so it must render to show them.
`DashboardView` passes `remindersLoading` (true while `load()` is in flight)
and renders nothing itself.

Update the existing `MorningBoardView(board:ordersById:)` call site in `DashboardView` (DashboardView.swift:36) to pass the four new arguments (`drafts: reminderDrafts`, `remindersLoading: loading`, and the two closures).

- [ ] **Step 3: `RemindersSectionView`** — stateless renderer. Requirements (all from spec Unit 7; each is a checklist item, not a nicety):

  - **Loading state** (spec Unit 7, explicitly called out there as a prior omission): while `isLoading`, render `ProgressView()` + "Checking reminders…" instead of rows.
  - Header `Label("Reminders", systemImage: "bell.badge")` + count with **real plural forms**: `1 reminder` / `2 reminders`, never `reminder(s)`. Count comes from the **post-filter** rendered list.
  - Row: kind icon (`ruler` / `indianrupeesign.circle` / `checkmark.seal`), customer name, context line (order # · `Formatters.inr(amountDue)` when present · fitting time), message preview `.lineLimit(2)`.
  - Two buttons — **"Send on WhatsApp"** and **"Mark done"** — each `.frame(minWidth: 44, minHeight: 44)` with ≥8pt spacing (Apple Design §3.1).
  - Explainer line: "Sending opens WhatsApp — tap Mark done once you've sent it." (Sending deliberately does not auto-mark.)
  - Empty state (when the section renders with zero rows): "No reminders right now — fittings, balances, and ready orders will appear here."
  - Each row `.accessibilityElement(children: .combine)` with a label naming customer + kind + action.
  - At the largest Dynamic Type size the row **wraps** rather than truncating the buttons — verify in the simulator with Accessibility Inspector.

  `onSend` calls `WhatsAppShareHelper.open(phone: draft.whatsappTarget, message: draft.message)`; `onMarkDone` calls `RemindersService.markDone(...)` then removes the draft locally (optimistic — the row disappears immediately; a failed insert surfaces via `ErrorBus`).

- [ ] **Step 4: `xcodegen generate` + FULL test suite + build** — green (**197**, no new tests in this task).

- [ ] **Step 5: Simulator QA** — create a fitting appointment for tomorrow on a consented customer, confirm the draft appears; tap Mark done; pull to refresh; confirm it does not return.

- [ ] **Step 6: Commit** `feat: R4a Reminders section on the Dashboard`

- [ ] **Step 7: Push** `git push origin main:boutique-360-ipad-app`

**Chunk A gate:** full suite green; the RLS round-trip verified with evidence; a marked-done draft stays gone across a refresh.

---

## Chunk B: R4b — PIN-scoped roles

### Task B1: `PinPolicy` + `RolePolicy` (TDD)

**Files:**
- Create: `ipad/Boutique360/Utilities/PinPolicy.swift`
- Create: `ipad/Boutique360/Utilities/RolePolicy.swift`
- Create: `ipad/Boutique360Tests/PinPolicyTests.swift`
- Create: `ipad/Boutique360Tests/RolePolicyTests.swift`

- [ ] **Step 1: Write both failing test suites.**

```swift
// PinPolicyTests.swift
import XCTest
@testable import Boutique360

final class PinPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // ── validate
    func testLengthBounds() {
        XCTAssertNil(PinPolicy.validate("1357"))
        XCTAssertEqual(PinPolicy.validate("135"), .tooShort)
        XCTAssertEqual(PinPolicy.validate("1357913"), .tooLong)
    }
    func testNonNumericRejected() {
        XCTAssertEqual(PinPolicy.validate("12a4"), .notNumeric)
    }
    func testTooSimpleRejectsIdenticalAndMonotonicRuns() {
        XCTAssertEqual(PinPolicy.validate("0000"), .tooSimple)
        XCTAssertEqual(PinPolicy.validate("111111"), .tooSimple)
        XCTAssertEqual(PinPolicy.validate("1234"), .tooSimple)
        XCTAssertEqual(PinPolicy.validate("4321"), .tooSimple)
        XCTAssertEqual(PinPolicy.validate("456789"), .tooSimple)
    }
    func testNonMonotonicAccepted() {
        // Disambiguates the rule: a strictly monotonic RUN is rejected,
        // not any PIN containing an adjacent ±1 pair.
        XCTAssertNil(PinPolicy.validate("1235"))
        XCTAssertNil(PinPolicy.validate("112233"))
        XCTAssertNil(PinPolicy.validate("1212"))
    }

    // ── attempt state machine
    func testFourFailuresDoNotLock() {
        var s = PinPolicy.AttemptState()
        for _ in 0..<4 { s = PinPolicy.afterAttempt(correct: false, state: s, now: t0) }
        XCTAssertEqual(PinPolicy.lockState(s, now: t0), .open)
    }
    func testFifthFailureStartsCooldown() {
        var s = PinPolicy.AttemptState()
        for _ in 0..<5 { s = PinPolicy.afterAttempt(correct: false, state: s, now: t0) }
        XCTAssertEqual(PinPolicy.lockState(s, now: t0), .cooldown(secondsRemaining: 30))
    }
    func testCooldownExpires() {
        var s = PinPolicy.AttemptState()
        for _ in 0..<5 { s = PinPolicy.afterAttempt(correct: false, state: s, now: t0) }
        XCTAssertEqual(PinPolicy.lockState(s, now: t0.addingTimeInterval(31)), .open)
    }
    func testAttemptWhileLockedIsNoOp() {
        var s = PinPolicy.AttemptState()
        for _ in 0..<5 { s = PinPolicy.afterAttempt(correct: false, state: s, now: t0) }
        let before = s
        s = PinPolicy.afterAttempt(correct: false, state: s, now: t0.addingTimeInterval(5))
        XCTAssertEqual(s, before, "a wrong tap during cooldown must not extend it")
    }
    func testCorrectAttemptClearsEverything() {
        var s = PinPolicy.AttemptState()
        for _ in 0..<4 { s = PinPolicy.afterAttempt(correct: false, state: s, now: t0) }
        s = PinPolicy.afterAttempt(correct: true, state: s, now: t0)
        XCTAssertEqual(s, PinPolicy.AttemptState())
        XCTAssertEqual(s.failuresSinceOwnerUnlock, 0)
    }

    // ── the clock-winding defence
    func testHardCapSurvivesClockWinding() {
        var s = PinPolicy.AttemptState()
        // 25 failures, walking the clock forward past each cooldown
        var now = t0
        for _ in 0..<25 {
            if case .cooldown = PinPolicy.lockState(s, now: now) { now = now.addingTimeInterval(31) }
            s = PinPolicy.afterAttempt(correct: false, state: s, now: now)
        }
        XCTAssertEqual(s.failuresSinceOwnerUnlock, PinPolicy.hardAttemptCap)
        XCTAssertEqual(PinPolicy.lockState(s, now: now), .capped)
        // Winding the device clock a year forward must NOT clear the cap
        XCTAssertEqual(PinPolicy.lockState(s, now: now.addingTimeInterval(31_536_000)), .capped)
    }
    func testCappedTakesPrecedenceOverCooldown() {
        var s = PinPolicy.AttemptState()
        s.failuresSinceOwnerUnlock = PinPolicy.hardAttemptCap
        s.lockedUntil = t0.addingTimeInterval(30)
        XCTAssertEqual(PinPolicy.lockState(s, now: t0), .capped)
    }
    func testRecoveryFromCapped() {
        // THE deadlock test: the cap must be escapable. This is the pure
        // half of the device-auth recovery path.
        var s = PinPolicy.AttemptState()
        s.failuresSinceOwnerUnlock = PinPolicy.hardAttemptCap
        XCTAssertEqual(PinPolicy.lockState(s, now: t0), .capped)
        s = PinPolicy.cleared()
        XCTAssertEqual(PinPolicy.lockState(s, now: t0), .open)
    }
}
```

```swift
// RolePolicyTests.swift
import XCTest
@testable import Boutique360

final class RolePolicyTests: XCTestCase {
    func testOwnerSeesEverything() {
        for s in RolePolicy.Surface.allCases {
            XCTAssertTrue(RolePolicy.canSee(s, role: .owner), "owner must see \(s)")
        }
    }
    func testAssistantSeesNoGatedSurface() {
        for s in RolePolicy.Surface.allCases {
            XCTAssertFalse(RolePolicy.canSee(s, role: .assistant), "assistant must NOT see \(s)")
        }
    }
    /// Tripwire: a bare allCases loop would pass automatically for a new
    /// case, so pin the count. Adding a surface fails here until someone
    /// consciously reviews it and bumps the number.
    func testSurfaceCountIsPinned() {
        XCTAssertEqual(RolePolicy.Surface.allCases.count, 10)
    }
}
```

- [ ] **Step 2: `xcodegen generate`, run both suites** — expect FAIL.

- [ ] **Step 3: Implement both files** per spec Unit 4. `PinPolicy.lockState` returns `.capped` when `failuresSinceOwnerUnlock >= hardAttemptCap` (checked **before** the cooldown branch), `.cooldown(secondsRemaining:)` when `lockedUntil > now`, else `.open`. `afterAttempt` is a no-op while `isLocked`. `cleared()` returns a fresh `AttemptState()`. `RolePolicy.Surface` has exactly the ten cases in the spec; `canSee` is `role == .owner`.

  **Countdown rounding:** `secondsRemaining = Int(ceil(lockedUntil.timeIntervalSince(now)))`. The tests sample at `t0` where all roundings agree, but truncation would show "23s" at `t0+6` — round up so the countdown never under-promises.

- [ ] **Step 4: Run both suites** — expect all PASS.

- [ ] **Step 5: Commit** `feat: PinPolicy + RolePolicy pure policies + tests`

### Task B2: KeychainStore hardening + PIN hashing

**Files:**
- Modify: `ipad/Boutique360/Services/KeychainStore.swift`
- Create: `ipad/Boutique360/Utilities/PinHasher.swift`
- Create: `ipad/Boutique360Tests/PinHasherTests.swift`

- [ ] **Step 1: Failing tests:**

```swift
import XCTest
@testable import Boutique360

final class PinHasherTests: XCTestCase {
    func testSameSaltAndPinProduceSameDigest() throws {
        let salt = PinHasher.newSalt()
        XCTAssertEqual(PinHasher.digest(pin: "1357", salt: salt),
                       PinHasher.digest(pin: "1357", salt: salt))
    }
    func testDifferentSaltProducesDifferentDigest() throws {
        let a = PinHasher.digest(pin: "1357", salt: PinHasher.newSalt())
        let b = PinHasher.digest(pin: "1357", salt: PinHasher.newSalt())
        XCTAssertNotEqual(a, b, "salts must differ per PIN set")
    }
    func testVerifyAcceptsCorrectAndRejectsWrong() throws {
        let stored = PinHasher.makeStored(pin: "1357")
        XCTAssertTrue(PinHasher.verify(pin: "1357", stored: stored))
        XCTAssertFalse(PinHasher.verify(pin: "1358", stored: stored))
    }
    func testStoredFormatCarriesNoPlaintext() throws {
        let stored = PinHasher.makeStored(pin: "1357")
        XCTAssertFalse(stored.contains("1357"), "the PIN must never appear in the stored blob")
        XCTAssertTrue(stored.contains(":"), "expected salt:digest")
    }
    func testMalformedStoredBlobFailsClosed() {
        XCTAssertFalse(PinHasher.verify(pin: "1357", stored: "garbage"))
        XCTAssertFalse(PinHasher.verify(pin: "1357", stored: ""))
    }
}
```

- [ ] **Step 2: Run — FAIL.**

- [ ] **Step 3: Implement `PinHasher.swift`:**

```swift
import Foundation
import CryptoKit
import Security   // SecRandomCopyBytes lives here — NOT re-exported by
                  // Foundation or CryptoKit. Same import KeychainStore uses.

/// R4b — the PIN is never stored in plaintext (Security §2, §6).
/// Stored form: "<base64 salt>:<base64 SHA256(salt ‖ pin)>".
enum PinHasher {
    static func newSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    static func digest(pin: String, salt: Data) -> Data {
        var input = salt
        input.append(Data(pin.utf8))
        return Data(SHA256.hash(data: input))
    }

    static func makeStored(pin: String) -> String {
        let salt = newSalt()
        return "\(salt.base64EncodedString()):\(digest(pin: pin, salt: salt).base64EncodedString())"
    }

    /// Constant-time comparison — no early exit on first differing byte.
    static func verify(pin: String, stored: String) -> Bool {
        let parts = stored.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let salt = Data(base64Encoded: String(parts[0])),
              let expected = Data(base64Encoded: String(parts[1])) else { return false }
        let actual = digest(pin: pin, salt: salt)
        guard actual.count == expected.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(actual, expected) { diff |= a ^ b }
        return diff == 0
    }
}
```

- [ ] **Step 4: Add the accessibility parameter to `KeychainStore.save`** — default preserves today's behavior so existing callers are untouched:

```swift
@discardableResult
static func save(_ value: String, forKey key: String,
                 accessible: CFString = kSecAttrAccessibleAfterFirstUnlock) -> Bool {
    // … existing body, but:
    attrs[kSecAttrAccessible as String] = accessible
    // …
}
```

Role/PIN callers pass `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — **excluded from iCloud/iTunes backups** (Security §2: "backups don't leak sensitive data").

- [ ] **Step 5: Run tests + build** — green.

- [ ] **Step 6: Commit** `feat: PIN hashing (salted SHA256, constant-time) + Keychain accessibility param`

### Task B3: `EventsService.record` + `StaffRoleContext`

**Files:**
- Modify: `ipad/Boutique360/Services/EventsService.swift` (append)
- Modify: `ipad/Boutique360/Info.plist` (after the existing `*UsageDescription` keys, ~line 58)
- Create: `ipad/Boutique360/Services/StaffRoleContext.swift`

- [ ] **Step 1: `EventsService.record`:**

```swift
/// R4b — audit trail for security-relevant actions (Security §12).
/// `events.actor_type` already permits 'ipad' (migration 0004).
static func record(boutiqueId: UUID, eventName: String,
                   payload: [String: String], actorType: String = "ipad") async throws {
    struct NewEvent: Encodable {
        let boutique_id: UUID
        let actor_type: String
        let event_name: String
        let payload_json: [String: String]
    }
    _ = try await SupabaseService.client.from("events")
        .insert(NewEvent(boutique_id: boutiqueId, actor_type: actorType,
                         event_name: eventName, payload_json: payload))
        .execute()
}
```

- [ ] **Step 2: `Info.plist`** — add (Security §5: maps to a reachable shipping feature):

```xml
<key>NSFaceIDUsageDescription</key>
<string>Boutique 360 uses Face ID to restore owner mode when the assistant PIN is locked out.</string>
```

- [ ] **Step 3: Implement `StaffRoleContext.swift`** per spec Unit 5. Key requirements:

  - `@MainActor final class StaffRoleContext: ObservableObject`, `@Published private(set) var role: StaffRole`.
  - **Persistence is what makes this real:** `role` and `AttemptState` are JSON-encoded into the Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and **restored in `init()`**. A force-quit must not escape assistant mode or clear a lockout.
  - `setPin`/`changePin` → `PinPolicy.validate` → `PinHasher.makeStored` → Keychain.
  - `handOverToAssistant()` — no PIN required (reducing privilege).
  - `unlockToOwner(pin:) -> UnlockResult { ok, wrong(remaining:), cooldown(seconds:), capped }`.
  - `unlockToOwnerWithDeviceAuth() async -> DeviceAuthResult` — **the cap's only escape.** Three things the implementer must get right:
    1. **Hold the context** — `let ctx = LAContext()` as a local for the call's lifetime; a temporary can be released mid-evaluation.
    2. **Probe first** so B4 can produce the required no-passcode copy:
       ```swift
       import LocalAuthentication

       enum DeviceAuthResult { case ok, noPasscodeSet, cancelledOrFailed }

       func unlockToOwnerWithDeviceAuth() async -> DeviceAuthResult {
           let ctx = LAContext()
           var probeError: NSError?
           guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &probeError) else {
               // LAError.passcodeNotSet is the case the UI must name specifically.
               if (probeError as? LAError)?.code == .passcodeNotSet { return .noPasscodeSet }
               return .cancelledOrFailed
           }
           do {
               let ok = try await ctx.evaluatePolicy(
                   .deviceOwnerAuthentication,
                   localizedReason: "Restore owner mode")
               guard ok else { return .cancelledOrFailed }
           } catch {
               return .cancelledOrFailed
           }
           // success → clear the cap, restore owner, persist, audit
           …
           return .ok
       }
       ```
    3. **Async availability:** `evaluatePolicy(_:localizedReason:)` has an `async throws` overload on the iOS 17 SDK. If the build errors on it, wrap the completion-handler API in `withCheckedThrowingContinuation` — do **not** silently fall back to a synchronous/blocking call.

    On `.ok`: `PinPolicy.cleared()`, role `.owner`, persisted, audited as `staff.unlock_device_auth`.
  - Audit every transition: `staff.role_changed` `{from,to}`, `staff.unlock_failed` (**no PIN material in the payload**), `staff.unlock_device_auth`. Audit failures are non-fatal → `ErrorBus`.
  - **Keychain-failure handling differs by direction** (spec Error handling — conflating them is a security bug):
    - `unlockToOwner` persist fails → **refuse** the unlock (fail closed).
    - `handOverToAssistant` persist fails → **apply the in-memory downgrade anyway** and surface: "Handed over, but this device will return to owner mode if the app restarts." Refusing here is fail-*open* — the iPad is already across the table.
  - Inject in `Boutique360App.swift` as an `@StateObject` alongside `BoutiqueContext`.

- [ ] **Step 4: `xcodegen generate` + build** — green.

- [ ] **Step 5: Commit** `feat: StaffRoleContext (persisted role + lockout, device-auth recovery) + audit events`

### Task B4: Role UI

**Files:**
- Create: `ipad/Boutique360/Features/Settings/PinEntrySheet.swift`
- Create: `ipad/Boutique360/Features/Settings/StaffRoleSection.swift`
- Modify: `ipad/Boutique360/Features/Settings/SettingsView.swift`
- Modify: `ipad/Boutique360/Features/Shell/AppShellView.swift` (assistant-mode indicator)

- [ ] **Step 1: `PinEntrySheet`** — modes set / change / unlock. The three `LockState` cases get **three distinct treatments** (Content §3 — a stuck timer where there is no countdown would be a lie):
  - `.open` → normal secure numeric entry.
  - `.cooldown(s)` → entry disabled + live countdown: "Too many attempts. Try again in 24s."
  - `.capped` → entry disabled, **no countdown**, prominent **"Unlock with Face ID / device passcode"** button: "Too many wrong PINs. Use this iPad's passcode to restore owner mode."
  - The device-passcode affordance also appears in `.open` — an owner who forgets the PIN is not stranded.
  - If `evaluatePolicy` fails because no device passcode is set: "This iPad has no passcode set, so owner mode can't be restored this way. Set a device passcode in Settings."
  - Validation errors in plain language: "PIN must be 4–6 digits", "Choose a less predictable PIN". **Never echo the PIN.**

- [ ] **Step 2: `StaffRoleSection`** in `SettingsView` — states: no PIN → "Set assistant PIN"; PIN + owner → "Hand over to assistant" + "Change PIN"; PIN + assistant → "Unlock as owner".

- [ ] **Step 3: Assistant-mode indicator** in `AppShellView` — a persistent badge so the active role is never ambiguous (Apple Design Principle 1).

- [ ] **Step 4: Build** — green. **Step 5: Commit** `feat: role UI — PIN entry, hand-over, assistant indicator`

### Task B5: Surface gating + the audit

**Files (gated — each consults `RolePolicy.canSee(_:role:)`, hidden not disabled). Every surface has a named anchor so nothing is left to interpretation:**

| Surface | File · what exactly |
|---|---|
| `.payments` | `Features/Orders/PaymentsSectionView.swift` — the whole `Section` |
| `.razorpayLink` | `PaymentsSectionView.swift` — "Create payment link" button + the inline URL + the hard-coded `₹` in its WA message (line ~180) |
| `.revenueTile` | `Features/Dashboard/DashboardView.swift` — `todaysRevenueCard` |
| `.paymentReminders` | `DashboardView.swift` — `paymentsOverdueSection`; `MorningBoardView.swift` — needs-you `deliverAndCollect` amount text; `RemindersSectionView` — payment-kind drafts |
| `.moneyDueTile` | `MorningBoardView.swift` — the "Money due" tile |
| `.spendPanel` | `Features/Customers/CustomerSpendSummaryView.swift` — whole view; also audit `CustomerDetailView.swift` for money rows |
| `.invoice` | `Features/Orders/OrderDetailView.swift` — "Generate invoice" button **and** the `.sheet` presenting `InvoicePreviewView.swift` (separate file — gate the entry point so the sheet is unreachable) |
| `.gstExport` | `Features/Settings/SettingsView.swift` — `gstExportSection` |
| `.settingsSensitive` | `SettingsView.swift` — the "Integrations" section (credential status) and `EditBoutiqueView` entry (GSTIN/address) |
| `.lockPricing` | `Features/Orders/LockSheet.swift` — price-breakup fields + advance row; `LockSummarySheet.swift` — breakup rows + advance + CO price deltas |

- [ ] **Step 1: VERIFICATION TASK — the surface audit.** *(Reviewer-flagged: these live outside the new files and are easy to miss in a diff review.)*

  **Money is rendered through per-file private helpers (`formatINR(...)`, `format(...)`), not `Formatters.inr` directly — a naive grep misses the actual render sites.** Use:
  ```bash
  cd ipad && grep -rnE "Formatters\.inr|formatINR|format\(|deliverAndCollect|amountDue|₹" Boutique360/Features/
  ```
  Audit **every** file including `LockSheet.swift` and `LockSummarySheet.swift` (they carry `.lockPricing` — they are subjects of the audit, not exclusions).

  Known render sites that MUST appear in your triage list (from the reviewer's sweep — if your grep misses any of these, your pattern is wrong):
  - `DashboardView.swift:219` — `formatINR(o.total)` in `paymentsOverdueSection` → `.paymentReminders`
  - `PaymentsSectionView.swift:35,36,46,54,64,218` → `.payments`
  - `PaymentsSectionView.swift:180` — **hard-coded `₹\(Int(balanceDue))`** in the Razorpay WhatsApp message → `.razorpayLink`
  - `OrderDetailView.swift:101,108–114` → `.invoice`
  - `OrdersListView.swift:191,197` · `OrderCreateView.swift:98–101` → triage explicitly (order totals in a list/create form — decide and comment)
  - `CustomerDetailView.swift` (money in the customer hub) → triage; likely `.spendPanel`

  **Pass criteria:** every hit is either (a) inside a view gated by `RolePolicy`, or (b) consciously classified as non-sensitive with a one-line code comment saying why. Paste the full triage list into the commit message. An un-triaged hit is a failed audit, not a TODO.

- [ ] **Step 2: Apply the gating.** Pattern:
  ```swift
  @EnvironmentObject private var roles: StaffRoleContext
  // …
  if RolePolicy.canSee(.payments, role: roles.role) { paymentsSection }
  ```
  In `RemindersSectionView`, filter payment-kind drafts when `!canSee(.paymentReminders, …)` — and compute the header count **after** filtering, so an assistant never sees "5 reminders" above three rows.

- [ ] **Step 3: FULL test suite + build** — green (**217** = 197 + PinPolicy 12 + RolePolicy 3 + PinHasher 5).

- [ ] **Step 4: Manual QA** (spec Testing section — this is what proves the design, not the unit tests):
  1. Set PIN → hand over → **every gated surface hidden**.
  2. **Force-quit and relaunch → still assistant.**
  3. Wrong PIN ×5 → cooldown copy with countdown.
  4. **Force-quit → cooldown still active.**
  5. Correct PIN → owner restored.
  6. Wrong PIN ×25 → `.capped` copy, **no countdown**, device-passcode button.
  7. **Wind the device clock forward in iOS Settings → still capped.**
  8. Face ID / device passcode → owner restored.
  9. `select * from events where event_name like 'staff.%'` → transitions logged, **no PIN material in any payload**.

- [ ] **Step 5: Commit** `feat: R4b surface gating + audit` (include the Step 1 audit list) — **Step 6: Push.**

**Chunk B gate:** full suite green; all nine manual QA steps pass — particularly 2, 4 and 7, which are the ones that distinguish a real gate from security theatre.

---

## Chunk C: Compliance deliverables

### Task C1: `LICENSE` + `SECURITY_REVIEW.md`

- [ ] **Step 1:** `LICENSE` — proprietary / all-rights-reserved (Documentation §1 [R]). **ASK THE HUMAN for the legal holder name** (personal name vs a registered entity) — do not invent one; a licence naming the wrong party is worse than none. Format: `Copyright (c) 2026 <holder>. All rights reserved.` plus a line stating no permission is granted to copy, modify, or distribute.
- [ ] **Step 2:** `SECURITY_REVIEW.md` — dated full pass of Security & Privacy §1–§12. Include the Unit 6 threat model **verbatim**, and state plainly: the role gate is a same-device UI boundary, not server-side authorization; anyone with the session token or Supabase dashboard reads everything regardless of role; server-side RBAC requires per-staff accounts (deferred). Do not tick §6 without that caveat.
- [ ] **Step 3: Commit** `docs: LICENSE + SECURITY_REVIEW`

### Task C2: `DATA_HANDLING.md` + `RELEASE_CHECKLIST.md` + privacy-policy verification

- [ ] **Step 1:** `docs/DATA_HANDLING.md` — App Privacy / Play Data Safety answers grounded in **real** flows (copy-paste ready for the store form).
- [ ] **Step 2:** `docs/RELEASE_CHECKLIST.md` — project-specific instantiation of the Release checklist: version bump, migration deploy, **demo-flag off**, prod keys, TestFlight, rollback path.
- [ ] **Step 3:** Verify `docs/privacy-policy.md` covers every **current** flow — karigar WIP photos (`karigar-wip` bucket), `reminder_log`, role audit events. **Update, don't recreate.**
- [ ] **Step 4: Commit** `docs: DATA_HANDLING + RELEASE_CHECKLIST + privacy-policy refresh`

### Task C3: Adherence register + living docs

- [ ] **Step 1:** `docs/compliance/template-adherence.md` — all six checklists + the Testing PDF, section by section, ✅/⚠️/❌/N-A with **evidence** (file:line) and an owner per gap. Declared gaps, stated honestly rather than papered over: no i18n String Catalog / `.stringsdict`; no automated dependency scanning; no certificate pinning; store assets not started; server-side RBAC deferred; escalating lockout deferred. Record the stated principle: **copy follows the security rule, not the other way round.**
- [ ] **Step 2:** Living docs — `docs/app-map.md` (§2 Dashboard + Settings rows, §7 R4a/R4b ✅), `README.md` (roadmap + test count), `CHANGELOG.md`, `CLAUDE.md` (speed-dial: `ReminderDrafts`, `PinPolicy`, `RolePolicy`, `StaffRoleContext`; migration count 30).
- [ ] **Step 3: Commit** `docs: template adherence register + living docs` — **Step 4: Push.**

**Chunk C gate:** every checklist section has a verdict and every ❌/⚠️ has a named owner. A register that claims more compliance than the code delivers is worse than no register.
