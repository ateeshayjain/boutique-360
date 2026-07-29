# Design: Auto-drafted reminders (R4a) + PIN-scoped roles (R4b)

**Date:** 2026-07-28 · **Status:** approved by owner; revised after spec review
**Roadmap items:** R4a, R4b (the remaining competitive absorbs from
`docs/competitive/darzi-ai-teardown.md` §4.1–4.2).
**Depends on:** R2 morning board (shipped — supplies R4a's inputs),
`KeychainStore` (shipped), `events` table + `events_insert` policy (shipped;
`actor_type` check already permits `'ipad'` — migration 0004).

**Template adherence:** first wave built under strict adherence to the six
standard checklists supplied (Apple Design Framework, Content & Localization,
Documentation, Performance & Reliability, Release, Security & Privacy) plus
the Testing Checklist PDF. Section citations below are load-bearing, not
decorative. Compliance deliverables ship in Unit 8.

## Problem

1. Darzi AI fires trial/payment/ready reminders automatically; we make the
   owner compose each one. Keep human review (ADR 0005), remove the composing.
2. Darzi AI has PIN-scoped staff access; whoever holds our iPad sees every
   rupee.

## Goals

- **R4a:** a Dashboard Reminders section of auto-drafted messages (fitting /
  payment / ready), each one tap from a prefilled `wa.me` compose, with a
  persistent "done" record so handled drafts don't reappear.
- **R4b:** owner ↔ assistant switching on one iPad — PIN hashed in the
  Keychain, **role and lockout persisted across app restarts**, money
  surfaces hidden in assistant mode, rate limited, audit logged.
- **Compliance:** adherence register, SECURITY_REVIEW.md, LICENSE, the three
  missing [R] docs, living docs updated.

## Non-goals (YAGNI)

- Auto-send without owner review (ADR 0005 stands).
- Background/scheduled draft notifications.
- Multi-user Supabase accounts / server-side RBAC (Unit 6 states the real
  threat model; server-side authorization is explicitly deferred).
- Per-permission granularity beyond owner/assistant.
- i18n String Catalog migration (declared gap, Unit 8).

---

## Unit 1 — Migration 0030: `reminder_log`

```sql
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
-- insert policies only; no update/delete policy → RLS denies them.
create policy "reminder_log_select" on public.reminder_log for select to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "reminder_log_insert" on public.reminder_log for insert to authenticated
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "reminder_log_service" on public.reminder_log for all to service_role
  using (true) with check (true);
```

The unique constraint IS the dedup mechanism — marking done twice is a 23505
the client treats as success. Retention (Security §11): FK ids only, no PII,
cascades with the boutique; no purge job.

**Pre-flight check (from review):** `current_setting('app.boutique_id')` is
transaction-local and no client call site for `set_boutique_id_from_user()`
exists. Whatever makes the shipped tables work applies identically here, but
the implementer MUST verify a round-trip insert+select from the app before
declaring the task done — if the app relies on the `authenticated` role
seeing rows another way, `reminder_log` inherits the same behavior and this
is not a regression, just an unverified assumption to close.

## Unit 2 — `Utilities/ReminderDrafts.swift` (pure, tested)

```swift
enum ReminderDrafts {
    /// `fitting` matches AppointmentType.fitting — the app's own term
    /// (Content §4: one term per concept). There is no "trial" type.
    enum Kind: String, Equatable, CaseIterable { case fitting, payment, ready }

    struct Draft: Equatable, Identifiable {
        let kind: Kind
        let subjectId: UUID
        let forDate: String          // YYYY-MM-DD, semantics per kind below
        let customerId: UUID
        let customerName: String
        let whatsappTarget: String   // NON-optional: no target ⇒ no draft
        let message: String
        let orderNumber: String?
        let amountDue: Double?       // payment kind only; rendered via Formatters.inr
        var id: String { ReminderDrafts.key(kind: kind, subjectId: subjectId, forDate: forDate) }
    }

    /// THE single key format. Both the draft builder and RemindersService
    /// MUST call this — never interpolate by hand. `uuidString` is uppercase
    /// in Swift and lowercase from Postgres, so the service lowercases both
    /// sides via this function after decoding to UUID.
    static func key(kind: Kind, subjectId: UUID, forDate: String) -> String {
        "\(kind.rawValue)-\(subjectId.uuidString.lowercased())-\(forDate)"
    }

    static func build(appointments: [Appointment],
                      orders: [Order],
                      jobCardsByOrder: [UUID: JobCard],
                      latestEventByCard: [UUID: JobCardEvent],
                      receivedByOrder: [UUID: Double],
                      customersById: [UUID: Customer],
                      logged: Set<String>,
                      boutiqueName: String,
                      today: Date,
                      calendar: Calendar = .current) -> [Draft]
}
```

### Inclusion rules

| Kind | Rule | `forDate` | Recurs after "done"? |
|---|---|---|---|
| `fitting` | `type == .fitting`, `status == .scheduled`, `scheduledAt` is today **or** tomorrow | **the appointment's date** | No — one reminder per appointment, ever |
| `payment` | status ∉ {pending, cancelled, returned}, `Money.roundedToPaise(total − received) > 0`, `(placedAt ?? createdAt)` ≥ 7 days old | **today** | **Yes — deliberately.** A dismissed nudge returns tomorrow because the balance is still owed; that's the point of a nudge |
| `ready` | done-signal true (job card `.ready`/`.delivered` OR latest karigar event `.ready`), order status ∉ {delivered, cancelled, returned} | **today** | Yes — same reasoning |

The payment rule excludes `.pending` to match the shipped
`DashboardView.filterOverdue` definition exactly (Content §4 / Apple
Principle 2 — the same order must not be "overdue" in one section and not in
another).

**Consent gate (DPDP, Security §10):** a draft is produced only when
`customer.consentWhatsapp == true` AND `customer.whatsappTarget != nil`.
No consent or no number ⇒ **no draft at all**, not a disabled row. We don't
surface prompts to message people who declined or can't be reached. This is
why `Draft.whatsappTarget` is non-optional.

**Known coverage limit:** `OrdersService.list()` caps at 200 rows, so
payment/ready drafts cover the 200 most recent orders. Acceptable at pilot
scale; recorded here rather than implied away.

**Sort:** fitting (earliest `scheduledAt` first) → ready → payment (largest
balance first); ties by `customerName`, then `subjectId.uuidString` — fully
deterministic for tests.

### Message copy (Content §1–2, §4)

Copied **verbatim** from the shipped strings so the customer hears one voice:
- payment — matches `PaymentsSectionView.swift:90` exactly:
  `"Hi {first}, a gentle reminder — balance of {inr} is pending on order {orderNo}. UPI / card / cash all accepted. Thank you! — {boutique}"`
- ready — matches `CustomerNotifier.orderReadyPlan` exactly, including the
  `Total:` clause.
- fitting — new string, app terminology ("fitting", not "trial"):
  `"Namaste {first}! Reminder — aapki fitting {day} ko {time} baje hai. — {boutique}"`

All money rendered via `Formatters.inr` (Content §5); never hand-formatted.

## Unit 3 — `Services/RemindersService.swift`

```swift
enum RemindersService {
    /// Window: today → tomorrow (matches the fitting lookahead; payment/ready
    /// use forDate == today, which is inside it).
    static func loggedKeys(boutiqueId: UUID, from: String, to: String) async throws -> Set<String>
    static func markDone(boutiqueId: UUID, kind: ReminderDrafts.Kind,
                         subjectId: UUID, forDate: String) async throws
}
```

`loggedKeys` decodes rows to (kind, subjectId: UUID, forDate) and builds keys
via `ReminderDrafts.key(...)` — the single format function. `markDone`
treats 23505 as success.

## Unit 4 — `Utilities/PinPolicy.swift` + `RolePolicy.swift` (pure, tested)

```swift
enum StaffRole: String, Codable { case owner, assistant }

enum PinPolicy {
    static let minLength = 4
    static let maxLength = 6
    static let maxAttempts = 5
    static let lockoutSeconds: TimeInterval = 30

    enum SetError: Equatable { case tooShort, tooLong, notNumeric, tooSimple }
    /// `tooSimple` rejects all-same-digit (0000) and strict run (1234/4321)
    /// PINs — Security §6 weak-credential rule.
    static func validate(_ pin: String) -> SetError?

    struct AttemptState: Equatable, Codable {
        var failures: Int = 0
        var lockedUntil: Date?
    }
    /// Pure. Rules:
    /// - while locked (`isLocked`), an attempt is a NO-OP: state unchanged,
    ///   lockout is NOT extended (a wrong tap during cooldown shouldn't
    ///   restart the clock; the caller refuses the attempt anyway).
    /// - correct → cleared state.
    /// - incorrect → failures+1; on reaching maxAttempts, set
    ///   lockedUntil = now + lockoutSeconds and reset failures to 0.
    static func afterAttempt(correct: Bool, state: AttemptState, now: Date) -> AttemptState
    static func isLocked(_ state: AttemptState, now: Date) -> Bool
    static func secondsRemaining(_ state: AttemptState, now: Date) -> Int
}

enum RolePolicy {
    /// Every surface that shows money or configuration. Adding a case here
    /// forces a decision in `canSee` (see the exhaustiveness test).
    enum Surface: String, CaseIterable {
        case payments, revenueTile, moneyDueTile, spendPanel, invoice,
             gstExport, razorpayLink, lockPricing, settingsSensitive,
             paymentReminders          // ← R4a's payment drafts carry balances
    }
    static func canSee(_ surface: Surface, role: StaffRole) -> Bool
}
```

**Fixed from review:** `paymentReminders` closes the hole where assistant
mode hid the money tile while listing itemized outstanding balances one
section below. The implementer must also audit
`DashboardView.paymentsOverdueSection` (renders `Formatters.inr(o.total)`
per row) and `MorningBoardView`'s needs-you rows (`deliverAndCollect`
amounts) — both are gated under `paymentReminders`.

### PIN storage (Security §2, §6 — corrected)

The PIN is **never stored in plaintext**:
- Random 16-byte salt generated at set time.
- `hash = SHA256(salt ‖ pin)` via CryptoKit (system framework — no new
  dependency; Security §7).
- Keychain stores `salt:hash` (base64, colon-separated) under one key.
- Verification compares digests in **constant time**
  (`Data.constantTimeEquals` helper — no early-exit `==`).
- `KeychainStore` gains an **accessibility parameter**; role/PIN items use
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` so the credential is
  **excluded from iCloud/iTunes backups** (Security §2: "backups don't leak
  sensitive data"). Existing callers keep today's default — no behavior
  change outside this feature.
- The PIN never appears in logs, errors, or analytics (Security §2). Error
  copy names the problem, never the value.

## Unit 5 — `Services/StaffRoleContext.swift` (`@MainActor ObservableObject`)

Injected alongside `BoutiqueContext`.

- `@Published private(set) var role: StaffRole`
- **Persistence (the review's B3 fix):** `role` AND `AttemptState` are
  persisted in the Keychain (`…ThisDeviceOnly`, JSON-encoded) and **restored
  on launch**. An assistant who force-quits the app relaunches **still in
  assistant mode**, with any active lockout still counting down. This is what
  makes the gate meaningful rather than theatre.
- `var pinIsSet: Bool`
- `setPin(_:)` / `changePin(current:new:)` — validate → salt+hash → Keychain.
- `handOverToAssistant()` — no PIN needed to *reduce* privilege; persists +
  audits.
- `unlockToOwner(pin:) -> UnlockResult` where
  `enum UnlockResult { case ok, wrong(remaining: Int), locked(seconds: Int) }`
  — drives `PinPolicy`, persists the new `AttemptState`, audits.
- **Audit (Security §12):** every role change records via new
  `EventsService.record(...)`: `event_name "staff.role_changed"`,
  payload `{from, to}`, `actor_type "ipad"`. Failed unlock attempts record
  `"staff.unlock_failed"` (no PIN material in the payload). Audit-write
  failure is non-fatal (availability over audit completeness on a
  single-device app) but reported via `ErrorBus` — stated in
  SECURITY_REVIEW.md.

`EventsService` gains:
```swift
static func record(boutiqueId: UUID, eventName: String,
                   payload: [String: String], actorType: String = "ipad") async throws
```

## Unit 6 — Threat model (stated here, not only in the compliance doc)

**What this gate is:** a same-device role boundary that survives app restart,
protecting money surfaces from a casual assistant using the boutique's iPad.

**What it is not:** server-side authorization. The app holds one Supabase
account; the anon key and session are on the device. Someone who extracts the
session token, or uses the Supabase dashboard, reads everything regardless of
role. **Server-side RBAC requires per-staff accounts with RLS on staff role —
deferred, and named as the mitigation in SECURITY_REVIEW.md.**

Also honest: a 4-digit PIN with a 30-second lockout after 5 attempts is
brute-forceable in ~17 hours of continuous tapping. Mitigations chosen: 6
digits allowed, weak PINs rejected, lockout persists across restarts, and
every failed attempt is audit-logged. Escalating lockouts deferred (YAGNI at
pilot scale) — recorded, not hidden.

## Unit 7 — UI

### R4a — `Features/Dashboard/RemindersSectionView.swift`

Rendered **inside `MorningBoardView`** between the needs-you list and the
pipeline strip (both live there — `MorningBoardView.swift:14–16`).
`MorningBoardView` gains a `drafts: [ReminderDrafts.Draft]` parameter plus
the two callbacks; `DashboardView` owns the state and passes them down.

- Header: `Label("Reminders", systemImage: "bell.badge")` + count with
  correct plural forms — `1 reminder` / `2 reminders`, never `reminder(s)`
  (Content §5).
- Row: kind icon (`ruler` / `indianrupeesign.circle` / `checkmark.seal`),
  customer name, context line (order # · `Formatters.inr(amountDue)` ·
  fitting time), message preview `lineLimit(2)`, then **"Send on WhatsApp"**
  and **"Mark done"** — action verbs (Content §2), each ≥44×44pt with ≥8pt
  spacing (Apple Design §3.1).
- Sending does **not** auto-mark done (the owner may cancel inside
  WhatsApp); a one-line explainer says so (Content §3).
- **Loading state:** `ProgressView` + "Checking reminders…" while drafts
  resolve (Content §3 — the review caught this omission).
- Empty state: "No reminders right now — fittings, balances, and ready
  orders will appear here." (Content §3.)
- Log-fetch failure → section hidden + existing stale-data banner (never
  risk duplicate sends).
- Assistant mode: payment-kind drafts filtered out via
  `RolePolicy.canSee(.paymentReminders, role:)`.
- Accessibility: each row is one combined element labelled with customer,
  kind, and action (Content §7). Dynamic Type to the largest size must not
  truncate the buttons — the row wraps to two lines instead (Content §6,
  Performance §9).

### R4b — role UI

- **`Features/Settings/StaffRoleSection.swift`** — set PIN / hand over /
  unlock / change PIN, states per `pinIsSet` + `role`.
- **`Features/Settings/PinEntrySheet.swift`** — secure numeric entry, modes
  set/change/unlock, plain-language `PinPolicy` errors ("PIN must be 4–6
  digits", "Choose a less predictable PIN"), lockout countdown ("Too many
  attempts. Try again in 24s.") — Content §3: disabled actions say why.
- **Assistant-mode indicator:** persistent badge in the app shell so the
  active role is never ambiguous (Apple Design Principle 1).
- **Gated surfaces** consult `RolePolicy.canSee`: `PaymentsSectionView`,
  Dashboard revenue card, money-due tile, `paymentsOverdueSection`,
  MorningBoard needs-you money amounts, `CustomerSpendSummaryView`, invoice
  button + preview, GST export, integrations rows, Razorpay link, LockSheet
  price-breakup + advance, LockSummarySheet money columns, Reminders payment
  drafts. **Hidden, not disabled** — an assistant shouldn't see the shape of
  what they can't access.
- Orders, designs, measurements, job cards, karigar links stay fully usable.

## Unit 8 — Compliance deliverables

1. **`docs/compliance/template-adherence.md`** — all six checklists + Testing
   PDF, section by section, ✅/⚠️/❌/N-A with evidence (file:line) and an
   owner per gap. Declared gaps (honest, not papered over):
   - **i18n:** inline Swift string literals, no String Catalog / `.stringsdict`
     (Content §6). Single-locale pilot (en-IN); migration tracked.
   - **Dependency scanning** (Security §7): no automated scanner; one SPM
     dependency (supabase-swift), manually reviewed.
   - **Certificate pinning** (Security §3): considered, not implemented —
     accepted pilot risk.
   - **Store assets / screenshots / age rating** (Release §5–6): pre-TestFlight.
   - **Server-side RBAC** (Security §6): deferred; Unit 6 threat model.
   - **Escalating lockout** (Security §6): deferred.
2. **`SECURITY_REVIEW.md`** — full §1–§12 pass, dated, with the Unit 6 threat
   model verbatim and open risks listed.
3. **`LICENSE`** — proprietary / all-rights-reserved, naming the holder
   (Documentation §1 [R]).
4. **The three missing [R] docs** the review flagged:
   - `docs/DATA_HANDLING.md` — App Privacy / Play Data Safety answers
     grounded in real flows (copy-paste ready).
   - `docs/RELEASE_CHECKLIST.md` — project-specific instantiation of the
     Release checklist (version bump, migration deploy, demo-flag check,
     TestFlight, rollback).
   - `docs/privacy-policy.md` exists — verify it covers every current flow
     (karigar WIP photos, reminder log, role audit events) and is
     publishable at a stable URL; update rather than recreate.
5. Living docs (Documentation §7): app-map §2/§7, README, CHANGELOG,
   CLAUDE.md speed-dial, api-rpcs note on `reminder_log`'s policy shape.

## Testing (Testing checklist; house rule: pure logic + Codable only)

- `ReminderDraftsTests`: per-kind inclusion + negative case; consent gate
  (no consent → no draft; no number → no draft); logged-key exclusion; key
  format round-trips with lowercase UUIDs; sort + tie-break determinism;
  payment age boundary at exactly 7 days; payment excludes `.pending`;
  ready excludes delivered; empty inputs → empty.
- `PinPolicyTests`: 4 ok / 3 short / 7 long / non-numeric / `0000` /
  `1234` rejected; 4 failures no lock; 5th locks; attempt while locked is a
  no-op (lockout not extended); correct resets; lockout expiry;
  `secondsRemaining`.
- `RolePolicyTests`: owner sees all; assistant sees none; **exhaustiveness
  is enforced by asserting `Surface.allCases.count == 10`** so adding a
  surface fails until the count and its classification are reviewed (the
  review correctly noted a bare all-cases loop is decorative here).
- Hash tests: same PIN + salt → same digest; different salt → different
  digest; constant-time comparator returns correct results (timing itself
  is not unit-testable — noted).
- Manual QA (Release §9, Testing PDF): set PIN → hand over → verify every
  gated surface hidden → **force-quit and relaunch → still assistant** →
  wrong PIN ×5 → lockout copy → **force-quit → lockout still active** →
  correct PIN → owner restored → audit rows present in `events`.

## Error handling

- Log fetch failure → section hidden + stale banner.
- `markDone` 23505 → success.
- Keychain save failure → inline error; PIN not considered set; role change
  refused rather than applied-but-unpersisted (fail closed).
- Audit write failure → non-fatal, `ErrorBus`, role change still applies.

## Build order

Migration 0030 (+ RLS round-trip verification) → ReminderDrafts + tests →
RemindersService → PinPolicy/RolePolicy + tests → KeychainStore
accessibility param + hashing helpers → StaffRoleContext +
EventsService.record → `xcodegen generate` → Reminders UI → role UI +
surface gating → compliance docs → living docs.
