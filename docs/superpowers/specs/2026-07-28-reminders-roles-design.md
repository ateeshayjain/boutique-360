# Design: Auto-drafted reminders (R4a) + PIN-scoped roles (R4b)

**Date:** 2026-07-28 · **Status:** approved by owner (this doc formalizes it)
**Roadmap items:** R4a, R4b (the two remaining competitive absorbs from
`docs/competitive/darzi-ai-teardown.md` §4.1–4.2).
**Depends on:** R2 morning board (shipped — supplies every input R4a needs),
`KeychainStore` (shipped), `events` table (shipped, read-only service).

**Template adherence:** this wave is the first built under strict adherence
to the seven standard checklists (Apple Design Framework, Content &
Localization, Documentation, Performance & Reliability, Release, Security &
Privacy, Testing). Section references below cite those documents. A repo-wide
adherence register + `SECURITY_REVIEW.md` ship in this wave (Unit 7).

## Problem

1. Darzi AI fires trial/payment/ready reminders automatically; Boutique 360
   makes the owner compose each one. We keep human review (ADR 0005) but
   remove the composing.
2. Darzi AI has PIN-scoped staff access so an assistant can't see the till;
   Boutique 360 shows every rupee to whoever holds the iPad.

## Goals

- **R4a:** a Reminders section on the Dashboard listing auto-drafted
  messages (trial / payment / ready), each one tap from a prefilled
  `wa.me` compose, with a persistent "done" record so a draft doesn't
  reappear after it's handled.
- **R4b:** owner ↔ assistant role switching on one iPad, PIN-protected in
  the Keychain, hiding money surfaces in assistant mode, with rate limiting
  and an audit trail.
- **Compliance:** adherence register, SECURITY_REVIEW.md, LICENSE, living
  docs updated.

## Non-goals (YAGNI)

- Automatic sending without owner review (ADR 0005 stands — the owner's
  finger is the send authority).
- Scheduled/background notifications for drafts (the board is pull-based;
  local notifications already exist for appointments).
- Multi-user Supabase accounts / server-side RBAC (single account today;
  Unit 6 documents this limitation honestly).
- Per-permission granularity beyond owner/assistant.
- i18n string catalog migration (tracked as an accepted gap in Unit 7).

---

## Unit 1 — Migration 0030: `reminder_log`

```sql
create table if not exists public.reminder_log (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  kind text not null check (kind in ('trial','payment','ready')),
  subject_id uuid not null,          -- appointment id (trial) or order id (payment/ready)
  for_date date not null,            -- the day the draft was for (natural key part)
  created_at timestamptz not null default now(),
  unique (boutique_id, kind, subject_id, for_date)
);
create index if not exists reminder_log_boutique_date_idx
  on public.reminder_log(boutique_id, for_date);
alter table public.reminder_log enable row level security;
-- Append-only for the app: select + insert policies only (same shape as
-- change_orders in 0029). No update/delete → a handled reminder stays handled.
create policy "reminder_log_select" on public.reminder_log for select to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "reminder_log_insert" on public.reminder_log for insert to authenticated
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "reminder_log_service" on public.reminder_log for all to service_role
  using (true) with check (true);
```

The unique constraint IS the dedup mechanism: marking done twice (double-tap,
two devices) is a 23505 the client treats as success. Retention: rows are
small and audit-useful; no purge (Security §11 — noted in SECURITY_REVIEW as
non-personal operational data, no deletion obligation beyond boutique cascade).

## Unit 2 — `Utilities/ReminderDrafts.swift` (pure, tested)

Consumes **only data the Dashboard already loads** (Performance §5: no new
queries) plus the reminder log.

```swift
enum ReminderDrafts {
    enum Kind: String, Equatable { case trial, payment, ready }

    struct Draft: Equatable, Identifiable {
        let id: String              // "\(kind)-\(subjectId)-\(forDate)" — stable, dedup-safe
        let kind: Kind
        let subjectId: UUID         // appointment id (trial) or order id (payment/ready)
        let forDate: String         // YYYY-MM-DD (Formatters.postgresDate)
        let customerId: UUID
        let customerName: String
        let whatsappTarget: String?  // nil → row shows "no WhatsApp number" and Send is disabled
        let message: String          // prefilled, owner-editable in WhatsApp
        let orderNumber: String?     // context line for payment/ready
        let amountDue: Double?       // payment kind only
    }

    /// Rules (all pure; every branch tested):
    /// - trial:   appointment of type trial/fitting scheduled TODAY or TOMORROW,
    ///            status == .scheduled, customer consented to WhatsApp.
    /// - payment: order not cancelled/returned, balance > 0 (roundedToPaise),
    ///            age of (placedAt ?? createdAt) >= 7 days, consented.
    /// - ready:   done-signal true (job card ready/delivered OR latest karigar
    ///            event .ready), order status not delivered/cancelled/returned,
    ///            consented.
    /// Exclusions: any draft whose (kind, subjectId, forDate) is in `logged`.
    /// Sort: trial (soonest appointment first) → ready → payment (largest
    ///       balance first); ties by customerName then subjectId for
    ///       determinism.
    static func build(appointments: [Appointment],
                      orders: [Order],
                      jobCardsByOrder: [UUID: JobCard],
                      latestEventByCard: [UUID: JobCardEvent],
                      receivedByOrder: [UUID: Double],
                      customersById: [UUID: Customer],
                      logged: Set<String>,          // "kind-subjectId-forDate" keys
                      boutiqueName: String,
                      today: Date,
                      calendar: Calendar = .current) -> [Draft]
}
```

**Consent rule (DPDP, Security §10):** a draft is only produced when
`customer.consentWhatsapp` is true AND `customer.whatsappTarget != nil`.
No consent → no draft at all (not a disabled row) — we don't surface
prompts to message people who declined.

**Message copy** (Content §1–2: plain language, action-oriented, no jargon;
reuses the tone already shipped in `OrderDetailView`/`PaymentsSectionView`):
- trial: `"Namaste {first}! Reminder — aapka trial {day} ko {time} baje hai. {boutique}"`
- payment: `"Hi {first}, gentle reminder — balance of {inr} is pending on order {orderNo}. UPI / card / cash all accepted. Thank you! — {boutique}"` (matches the existing reminder verbatim so the customer sees consistent voice — Content §4 terminology consistency)
- ready: `"Hi {first}, your order {orderNo} from {boutique} is ready! Drop by or reply for delivery."`

Pluralization (Content §5): counts in UI copy use proper singular/plural
(`1 reminder` / `2 reminders`), never `reminder(s)`.

## Unit 3 — `Services/RemindersService.swift`

```swift
enum RemindersService {
    /// Logged keys for a date window (today ± 1 day covers trial lookahead).
    static func loggedKeys(boutiqueId: UUID, from: String, to: String) async throws -> Set<String>
    /// Insert a done row; 23505 (already logged) is treated as success.
    static func markDone(boutiqueId: UUID, kind: ReminderDrafts.Kind,
                         subjectId: UUID, forDate: String) async throws
}
```

## Unit 4 — `Utilities/PinPolicy.swift` + `RolePolicy.swift` (pure, tested)

```swift
enum StaffRole: String, Codable { case owner, assistant }

enum PinPolicy {
    static let minLength = 4
    static let maxLength = 6
    static let maxAttempts = 5
    static let lockoutSeconds: TimeInterval = 30

    enum SetError: Equatable { case tooShort, tooLong, notNumeric, repeatedDigits }
    /// Validates a candidate PIN. `repeatedDigits` rejects 0000/1111-style PINs
    /// (Security §6 — weak credential).
    static func validate(_ pin: String) -> SetError?

    struct AttemptState: Equatable {
        var failures: Int
        var lockedUntil: Date?
    }
    /// Pure state machine. Correct PIN resets. Nth failure (N == maxAttempts)
    /// sets lockedUntil = now + lockoutSeconds and resets the counter.
    static func afterAttempt(correct: Bool, state: AttemptState, now: Date) -> AttemptState
    static func isLocked(_ state: AttemptState, now: Date) -> Bool
    static func secondsRemaining(_ state: AttemptState, now: Date) -> Int
}

enum RolePolicy {
    /// Surfaces that carry money or configuration.
    enum Surface: CaseIterable {
        case payments, revenueTile, moneyDueTile, spendPanel, invoice,
             gstExport, razorpayLink, lockPricing, settingsSensitive
    }
    /// Owner sees everything; assistant sees none of the above.
    static func canSee(_ surface: Surface, role: StaffRole) -> Bool
}
```

## Unit 5 — `Services/StaffRoleContext.swift` (`@MainActor ObservableObject`)

Single shared instance injected into the environment alongside
`BoutiqueContext`.

- `@Published private(set) var role: StaffRole` — **defaults to `.owner`**;
  when a PIN exists, the app starts in `.owner` (the owner unlocked the
  device) and the owner explicitly hands over.
- `var pinIsSet: Bool` — `KeychainStore.load(pinKey) != nil`.
- `setPin(_:)` / `changePin(current:new:)` — validate via `PinPolicy`,
  store via `KeychainStore.save` (Security §2: Keychain, never
  UserDefaults; PIN never logged, never in an error message).
- `handOverToAssistant()` — no PIN required to *reduce* privilege; logs the
  switch.
- `unlockToOwner(pin:) -> Bool` — compares against Keychain, drives
  `AttemptState` in memory (lockout does not survive app restart —
  documented limitation, acceptable for a shared-device UI gate).
- Every role change records an audit event via a new
  `EventsService.record(...)` (Security §12): `event_name`
  `"staff.role_changed"`, payload `{from, to}`, `actor_type: "ipad"`.
  Audit write failures are non-fatal (never block the switch) but are
  surfaced through `ErrorBus`.

`EventsService` gains:
```swift
static func record(boutiqueId: UUID, eventName: String,
                   payload: [String: String], actorType: String = "ipad") async throws
```

## Unit 6 — UI

### R4a — Dashboard "Reminders" section (`Features/Dashboard/RemindersSectionView.swift`)

Placed below the needs-you list, above the pipeline strip. Stateless
renderer over `[Draft]`.

- Header: `Label("Reminders", systemImage: "bell.badge")` + count with
  correct pluralization.
- Row: kind icon (trial `ruler` / payment `indianrupeesign.circle` /
  ready `checkmark.seal`), customer name, context line (order # · amount ·
  appointment time), one-line message preview (`lineLimit(2)`), then two
  buttons: **"Send on WhatsApp"** (opens `wa.me` via `WhatsAppShareHelper`)
  and **"Mark done"**. Both ≥44×44pt with ≥8pt spacing (Apple Design §3.1).
- Sending does NOT auto-mark done (the owner may cancel in WhatsApp);
  "Mark done" is the explicit record. Copy under the section explains this
  in one line (Content §3: disabled/ambiguous states must explain).
- No WhatsApp number on the customer → row renders with Send disabled and
  the reason inline: "No WhatsApp number on file" (Content §3).
- Empty state: "No reminders right now — trials, balances, and ready
  orders will appear here." (Content §3: empty states explain what goes
  here.)
- Failure of the reminder-log fetch → section hidden + the existing
  stale-data banner covers it (never show drafts we can't dedup, or the
  owner re-sends).
- Accessibility: each row is one combined element with a label naming the
  customer, kind, and action (Content §7).

### R4b — role UI

- **`Features/Settings/StaffRoleSection.swift`** in SettingsView:
  - PIN not set: "Set assistant PIN" → `PinEntrySheet` (set mode; validation
    errors from `PinPolicy` shown in plain language).
  - PIN set + owner: "Hand over to assistant" button + "Change PIN".
  - PIN set + assistant: "Unlock as owner" → `PinEntrySheet` (unlock mode)
    with lockout countdown when locked.
- **`Features/Settings/PinEntrySheet.swift`** — numeric secure field, mode
  set/change/unlock, ≥44pt keypad-friendly targets, error copy from
  `PinPolicy` (never echoes the PIN).
- **Assistant-mode banner:** a persistent, non-intrusive toolbar/badge
  indicator ("Assistant mode") so it's never ambiguous which role is active
  (Apple Design Principle 1: immediate recognition).
- **Gated surfaces** consult `RolePolicy.canSee(_:role:)`:
  `PaymentsSectionView`, Dashboard revenue card + money-due tile,
  `CustomerSpendSummaryView`, invoice button + `InvoicePreviewView`,
  GST export + integrations rows in Settings, Razorpay link button,
  LockSheet's price-breakup + advance rows and LockSummarySheet's money
  columns. Hidden entirely (not disabled) — an assistant shouldn't see
  the shape of what they can't access.
- Orders, designs, measurements, job cards, karigar links remain fully
  usable in assistant mode.

## Unit 7 — Compliance deliverables

1. **`docs/compliance/template-adherence.md`** — every section of all seven
   checklists → ✅ / ⚠️ / ❌ / N-A with evidence (file:line or doc link) and
   an owner for each gap. Known gaps to record honestly rather than paper
   over:
   - **i18n:** user-facing strings are inline Swift literals, not a String
     Catalog (Content §6). Single-locale pilot (en-IN); catalog migration
     tracked as a follow-up item, not claimed as done.
   - **Localized plurals:** manual singular/plural in new copy; no
     `.stringsdict`. Same follow-up.
   - **Store assets / screenshots / age rating** (Release §5–6): not started
     — pre-TestFlight.
   - **Dependency vulnerability scanning** (Security §7): no automated
     scanner wired; single SPM dependency (supabase-swift) reviewed manually.
   - **Certificate pinning** (Security §3): considered, not implemented —
     documented as accepted risk for pilot.
2. **`SECURITY_REVIEW.md`** — a full pass of the Security & Privacy
   checklist §1–§12 with the PIN/role model's limitation stated plainly:
   *the role gate is a shared-device UI boundary, not server-side
   authorization; a determined assistant with the iPad and Supabase
   credentials could read money data. Server-side RBAC requires per-staff
   accounts (deferred).*
3. **`LICENSE`** — proprietary/all-rights-reserved notice naming the holder
   (Documentation §1 [R]).
4. Living docs updated (Documentation §7): app-map §2/§7, README roadmap +
   counts, CHANGELOG, CLAUDE.md speed-dial, api-rpcs (no new RPCs this
   wave — note reminder_log's append-only policy shape).

## Testing (Testing checklist + house rule: pure logic only)

- `ReminderDraftsTests`: each kind's inclusion rule + its negative case;
  consent gate (no consent → no draft); no-WhatsApp-number → draft with nil
  target; logged key excludes; sort order + tie-break determinism; empty
  inputs → empty; payment age boundary at exactly 7 days; ready excludes
  delivered orders.
- `PinPolicyTests`: length bounds (4 ok, 3 too short, 7 too long),
  non-numeric, repeated-digit rejection, attempt state machine (4 failures
  no lock, 5th locks, correct resets), lockout expiry, secondsRemaining.
- `RolePolicyTests`: owner sees all surfaces; assistant sees none of the
  gated set; exhaustive over `Surface.allCases` so a new surface added later
  fails the test until classified.
- Decode test: `ReminderLog` row (if a model is needed) — otherwise the
  service returns keys only and no model is required.
- Manual QA (Release §9): fresh session → set PIN → hand over → verify every
  gated surface is hidden → wrong PIN ×5 → lockout copy → correct PIN →
  owner restored → audit rows present.

## Error handling

- Reminder-log fetch failure → section hidden + stale banner (never risk
  duplicate sends).
- `markDone` 23505 → treated as success (already handled).
- Keychain save failure → inline error in `PinEntrySheet`, PIN not
  considered set.
- Audit-event write failure → non-fatal; `ErrorBus` reports; role change
  still applies (availability over audit completeness on a single-user
  device — stated in SECURITY_REVIEW).

## Build order

Migration 0030 → ReminderDrafts + tests → RemindersService → PinPolicy +
RolePolicy + tests → StaffRoleContext + EventsService.record → Reminders
section UI → role UI + surface gating → compliance docs → living docs.
