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

    /// `logged` is non-optional by design: the caller MUST NOT call build()
    /// when the reminder-log fetch failed (no dedup ⇒ re-sends). That rule
    /// is the caller's contract, not this function's — see Unit 7.
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

One voice with the shipped strings (Content §4), with one deliberate
divergence for security:
- payment — matches `PaymentsSectionView.swift:90` **verbatim**:
  `"Hi {first}, a gentle reminder — balance of {inr} is pending on order {orderNo}. UPI / card / cash all accepted. Thank you! — {boutique}"`
- ready — matches `CustomerNotifier.orderReadyPlan` **minus its `Total:`
  clause**: `"Hi {first}, your order {orderNo} from {boutique} is ready! Drop by or reply for delivery."`
  **Why the divergence:** ready drafts are visible in assistant mode (only
  payment drafts are gated). Carrying the total would re-open exactly the
  leak `paymentReminders` closes. Money belongs in gated surfaces only, so
  **no draft that renders un-gated may contain a rupee amount** — this is the
  rule, and the copy follows it rather than the other way round.
- fitting — new string, app terminology ("fitting", not "trial"):
  `"Namaste {first}! Reminder — aapki fitting {day} ko {time} baje hai. — {boutique}"`

All money rendered via `Formatters.inr` (Content §5); never hand-formatted.

### Degraded-input rule (mirrors the board's own convention)

**Any `MorningBoard.Input` failure that feeds a draft kind suppresses that
kind entirely** — never a partial draft:
- `.payments` failed → **no payment drafts.** Non-negotiable: an empty
  `receivedByOrder` makes every balance look like the full order total, so
  the app would nudge customers for money they already paid.
- `.orders` failed → no payment and no ready drafts.
- `.jobCards` / `.events` failed → no ready drafts (the done-signal is
  unknown; better silent than wrong).
- `.appointments` failed → no fitting drafts.

`build(...)` takes `failedInputs: Set<MorningBoard.Input>` and applies these
suppressions before any other rule.

**Caller's contract (not a `build` rule):** if the reminder-log fetch failed,
the caller **must not call `build(...)` at all** and the section renders
hidden — without dedup the owner re-sends messages. `logged` stays
non-optional so this can't be fudged by passing an empty set (which would
look like "nothing handled yet" and re-surface every draft).

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
    /// Security §6 weak-credential rule. `tooSimple` rejects a PIN that is
    /// EITHER all-identical digits (0000, 111111) OR a **strictly monotonic
    /// run** — every step +1 (1234, 456789) or every step −1 (4321).
    /// Anything else is fine: 1235 ✓, 112233 ✓, 1357 ✓, 1212 ✓.
    static func validate(_ pin: String) -> SetError?

    struct AttemptState: Equatable, Codable {
        var failures: Int = 0
        var lockedUntil: Date?
        /// Monotonic across lockouts. Reset ONLY by a correct PIN entry or
        /// by device-owner re-auth (see hardAttemptCap). Backstop for the
        /// attacker-controlled clock (see Unit 6).
        var failuresSinceOwnerUnlock: Int = 0
    }
    /// Reaching this many failures since the last successful owner unlock
    /// stops accepting PIN attempts entirely — clock-independently.
    /// **Escape hatch: device-owner authentication** (Unit 5), NOT another
    /// PIN attempt. Without an escape this would deadlock: an assistant
    /// could tap 25 wrong PINs and permanently lock the owner out of their
    /// own till, with Keychain state surviving even app deletion. That
    /// would trade a confidentiality control for an availability
    /// vulnerability — not an acceptable exchange.
    static let hardAttemptCap = 25
    /// Pure. Rules:
    /// - while locked (`isLocked`), an attempt is a NO-OP: state unchanged,
    ///   lockout is NOT extended (a wrong tap during cooldown shouldn't
    ///   restart the clock; the caller refuses the attempt anyway).
    /// - correct → fully cleared state (including failuresSinceOwnerUnlock).
    /// - incorrect → failures+1 AND failuresSinceOwnerUnlock+1; on reaching
    ///   maxAttempts, set lockedUntil = now + lockoutSeconds and reset
    ///   failures (but NOT failuresSinceOwnerUnlock) to 0.
    static func afterAttempt(correct: Bool, state: AttemptState, now: Date) -> AttemptState
    /// Two distinct locked states — the UI must tell them apart, because
    /// only one of them has a countdown (Content §3):
    enum LockState: Equatable {
        case open
        case cooldown(secondsRemaining: Int)   // timed; wait it out
        case capped                            // needs device-owner re-auth
    }
    /// `.capped` takes precedence over `.cooldown`. Capped is
    /// clock-independent — winding the device clock forward cannot clear it.
    static func lockState(_ state: AttemptState, now: Date) -> LockState
    static func isLocked(_ state: AttemptState, now: Date) -> Bool   // != .open
    /// Clears failures + the cap. Called ONLY after a successful PIN entry
    /// or a successful device-owner re-auth.
    static func cleared() -> AttemptState
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
  `enum UnlockResult { case ok, wrong(remaining: Int), cooldown(seconds: Int), capped }`
  — drives `PinPolicy`, persists the new `AttemptState`, audits.
- **`unlockToOwnerWithDeviceAuth() async -> Bool`** — the cap's escape
  hatch. Runs `LAContext.evaluatePolicy(.deviceOwnerAuthentication, …)`
  (LocalAuthentication, a system framework — Security §7, no new
  dependency): Face ID / Touch ID with **device-passcode fallback**. Success
  → `AttemptState = .cleared()`, role → owner, persisted, audited as
  `staff.unlock_device_auth`. Rationale: the owner controls the iPad's
  passcode; the assistant does not. This is a *stronger* factor than the
  app PIN, so using it as the recovery path raises the floor rather than
  bypassing the control. Available whenever `.capped` — and offered as a
  secondary "Unlock with device passcode" affordance at any time.
  - `NSFaceIDUsageDescription` must be added to `Info.plist` ("Unlock owner
    mode to view payments and settings") — Security §5: every permission
    maps to a reachable shipping feature, and this one does.
  - If the device has no passcode set, `evaluatePolicy` fails; the UI then
    states plainly that a device passcode is required to recover owner mode
    (Content §3).
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
digits allowed, weak PINs rejected, lockout persists across restarts, every
failed attempt is audit-logged, and a **clock-independent hard cap** (25
failures since the last owner unlock) stops accepting PIN attempts entirely —
because `lockedUntil` is wall-clock and **an assistant on a shared iPad can
wind the device clock forward in iOS Settings to clear a timed lockout**. The
cap is the answer to that; the timed lockout alone is not.

**The cap's escape is device-owner authentication, never another PIN
attempt.** A cap with no escape would be worse than no cap: an assistant
taps 25 wrong PINs and permanently locks the owner out of their own till
(Keychain state survives app deletion) — trading confidentiality for an
availability vulnerability an adversary can trigger at will. Face ID /
device passcode is a factor the owner holds and the assistant doesn't, so
recovery raises the security floor instead of punching a hole in it.

Escalating lockout durations deferred (YAGNI at pilot scale) — recorded,
not hidden.

## Unit 7 — UI

### R4a — `Features/Dashboard/RemindersSectionView.swift`

Rendered **inside `MorningBoardView`** between the needs-you list and the
pipeline strip (both live there — `MorningBoardView.swift:14–16`).
`MorningBoardView` gains a `drafts: [ReminderDrafts.Draft]` parameter plus
the two callbacks; `DashboardView` owns the state and passes them down.

- Header: `Label("Reminders", systemImage: "bell.badge")` + count with
  correct plural forms — `1 reminder` / `2 reminders`, never `reminder(s)`
  (Content §5). **The count is computed from the post-filter list** (after
  assistant-mode payment filtering), so the header can never claim more rows
  than are shown.
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
  digits", "Choose a less predictable PIN"). The three `LockState` cases get
  three distinct treatments (Content §3 — a blocked action says why AND how
  to fix it):
  - `.open` → normal entry.
  - `.cooldown(s)` → entry disabled + live countdown: "Too many attempts.
    Try again in 24s."
  - `.capped` → entry disabled, **no countdown** (there isn't one), and a
    prominent **"Unlock with Face ID / device passcode"** button:
    "Too many wrong PINs. Use this iPad's passcode to restore owner mode."
    This is the recovery path; a stuck timer here would be a lie.
  - A secondary "Unlock with device passcode" affordance is available in
    the `.open` state too — the owner who forgot the PIN is not stranded.
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
  ready excludes delivered; empty inputs → empty; **degraded-input
  suppression, one test per rule — especially `.payments` failed → zero
  payment drafts** (the "nudge for money already paid" bug); no un-gated
  draft message contains a rupee amount.
- `PinPolicyTests`: 4 ok / 3 short / 7 long / non-numeric; `0000` and `1234`
  and `4321` rejected; `1235`, `112233`, `1357` accepted; 4 failures no
  lock; 5th locks; attempt while locked is a no-op (lockout not extended);
  correct resets everything including `failuresSinceOwnerUnlock`;
  `lockState` returns `.cooldown` with the right seconds, then `.open`
  after expiry; **hard cap: 25 failures → `lockState == .capped` even with
  `now` far in the future** (clock-winding defence); **`.capped` takes
  precedence over `.cooldown`**; **recovery: `cleared()` from the capped
  state returns `.open`** (the deadlock test — the cap must be escapable,
  and this is the pure half of the device-auth path).
- `RolePolicyTests`: owner sees all; assistant sees none; **exhaustiveness
  is enforced by asserting `Surface.allCases.count == 10`** so adding a
  surface fails until the count and its classification are reviewed (the
  review correctly noted a bare all-cases loop is decorative here).
- Hash tests: same PIN + salt → same digest; different salt → different
  digest; constant-time comparator returns correct results (timing itself
  is not unit-testable — noted).
- Manual QA (Release §9, Testing PDF): set PIN → hand over → verify every
  gated surface hidden → **force-quit and relaunch → still assistant** →
  wrong PIN ×5 → cooldown copy with countdown → **force-quit → cooldown
  still active** → correct PIN → owner restored → audit rows present in
  `events`. Then the cap path: wrong PIN ×25 → `.capped` copy with **no
  countdown** and the device-passcode button → **wind the device clock
  forward in iOS Settings → still capped** → device passcode / Face ID →
  owner restored, `staff.unlock_device_auth` logged.

## Error handling

- Log fetch failure → no drafts + stale banner (degraded-input rule, Unit 2).
- `markDone` 23505 → success.
- **Keychain save failure — the two directions differ, and conflating them
  is a security bug:**
  - `unlockToOwner` (privilege *up*): **refuse.** No persisted owner role,
    no owner session. Fail closed.
  - `handOverToAssistant` (privilege *down*): **apply the in-memory
    downgrade anyway**, then show a prominent warning — "Handed over, but
    this device will return to owner mode if the app restarts." Refusing
    here would be fail-*open*: the owner has already passed the iPad across
    the table while it still shows every rupee.
  - `setPin` failure → inline error; PIN not considered set.
- Audit write failure → non-fatal, `ErrorBus`, role change still applies.

## Build order

Migration 0030 (+ RLS round-trip verification) → ReminderDrafts + tests →
RemindersService → PinPolicy/RolePolicy + tests → KeychainStore
accessibility param + hashing helpers → `NSFaceIDUsageDescription` in
Info.plist → StaffRoleContext (incl. LocalAuthentication recovery) +
EventsService.record → `xcodegen generate` → Reminders UI → role UI +
surface gating → compliance docs → living docs.
