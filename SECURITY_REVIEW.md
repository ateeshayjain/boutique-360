# Security Review — Boutique 360

**Date:** 2026-07-31
**Scope:** the iPad app (`ipad/`), the Supabase backend (`supabase/`), and the
R4a/R4b changes that prompted this pass.
**Reviewer:** authored during the R4b build; **not independently reviewed.**
Treat every ✅ below as "the author checked this against the code," not as an
external audit finding.

This document is written to be useful when it is inconvenient. Where the
implementation is weaker than the feature name suggests, that is stated in the
body rather than in a footnote.

---

## 1. The headline caveat: the role gate is not authorization

R4b ships an owner/assistant role gate that hides payments, invoices, revenue,
and settings. It is important to be exact about what that does and does not
buy, because the feature's name invites over-reading.

**What it is:** a same-device role boundary that survives app restart,
protecting money surfaces from a casual assistant using the boutique's iPad.

**What it is not:** server-side authorization. The app holds one Supabase
account; the anon key and session are on the device. Someone who extracts the
session token, or uses the Supabase dashboard, reads everything regardless of
role. **Server-side RBAC requires per-staff accounts with RLS on staff role —
deferred, and named as the mitigation here.**

Concretely, in assistant mode the *data* is still fetched and still in memory;
only the rendering is suppressed. `RolePolicy.canSee` is a view-layer
predicate. Anyone with Xcode, a debugger, or the Supabase dashboard reads
everything. The control is meaningful against the actual pilot threat — an
assistant handed the iPad across the counter — and meaningless against a
technical adversary. Both halves of that sentence are load-bearing.

**Owner:** deferred to a future release; requires per-staff Supabase accounts.

---

## 2. Threat model for the PIN (reproduced verbatim from the design spec)

> Also honest: a 4-digit PIN with a 30-second lockout after 5 attempts is
> brute-forceable in ~17 hours of continuous tapping. Mitigations chosen: 6
> digits allowed, weak PINs rejected, lockout persists across restarts, every
> failed attempt is audit-logged, and a **clock-independent hard cap** (25
> failures since the last owner unlock) stops accepting PIN attempts entirely —
> because `lockedUntil` is wall-clock and **an assistant on a shared iPad can
> wind the device clock forward in iOS Settings to clear a timed lockout**. The
> cap is the answer to that; the timed lockout alone is not.
>
> **The cap's escape is device-owner authentication, never another PIN
> attempt.** A cap with no escape would be worse than no cap: an assistant
> taps 25 wrong PINs and permanently locks the owner out of their own till
> (Keychain state survives app deletion) — trading confidentiality for an
> availability vulnerability an adversary can trigger at will. Face ID /
> device passcode is a factor the owner holds and the assistant doesn't, so
> recovery raises the security floor instead of punching a hole in it.
>
> Escalating lockout durations deferred (YAGNI at pilot scale) — recorded,
> not hidden.

One property discovered during implementation and worth adding: because
`PinPolicy.afterAttempt` is a **no-op while locked**, the 25-failure cap is not
reachable by rapid tapping. An adversary must sit through five separate
30-second cooldowns to trigger it. This makes accidental self-lockout
substantially less likely than the raw number suggests.
Evidence: `ipad/Boutique360/Utilities/PinPolicy.swift:88`,
`ipad/Boutique360Tests/PinPolicyTests.swift` (`testHardCapSurvivesClockWinding`).

---

## 3. Credential storage

| Control | Status | Evidence |
|---|---|---|
| PIN never stored in plaintext | ✅ | `Utilities/PinHasher.swift` — 16-byte `SecRandomCopyBytes` salt, `SHA256(salt ‖ pin)`, stored `base64salt:base64digest` |
| Fresh salt per PIN set | ✅ | `PinHasher.makeStored`; `PinHasherTests.testDifferentSaltProducesDifferentDigest` |
| Constant-time comparison | ✅ | `PinHasher.verify` — XOR-accumulate, no early exit |
| Malformed stored blob fails closed | ✅ | `PinHasherTests.testMalformedStoredBlobFailsClosed` |
| PIN/role excluded from iCloud + iTunes backups | ✅ | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` in `Services/StaffRoleContext.swift`; parameter added in `Services/KeychainStore.swift` |
| PIN never logged, echoed, or sent in audit payloads | ✅ | `StaffRoleContext.audit` sends only a failure count; `PinEntrySheet.copy(for:)` names the problem, never the value |

**Deliberate non-use of a slow KDF.** The hash is plain salted SHA-256, not
PBKDF2/scrypt/Argon2. A 4–6 digit PIN has at most 10⁶ candidates, so no KDF
makes offline brute force expensive enough to matter; the real controls are
the `ThisDeviceOnly` Keychain item and the attempt cap. Recorded as a
conscious choice so a future reviewer doesn't read it as an oversight — but
note the corollary: **if the Keychain item is ever extracted, the PIN falls
immediately.** That is accepted, because an attacker with Keychain extraction
already has the session token (see §1).

---

## 4. Data at rest and in transit

- All Supabase traffic is HTTPS via the official SDK. **No certificate
  pinning** — declared gap, owner: future release. At pilot scale the
  realistic MITM risk is low; this is a known unmitigated item, not a solved
  one.
- Storage buckets are private by default with signed URLs. Two are public by
  design: `product-images` and `vto-results` (watermarked).
  Evidence: `Services/StorageService.swift:12–26`.
- **Signed URLs are never persisted** — the app stores `(bucket, path)` and
  regenerates at view time. This is a correctness rule (URLs expire in 1 hour)
  that doubles as a security one: no long-lived credential-bearing URL sits in
  a database row.
- Customer VTO photos auto-purge after 7 days via the `purge-expired-tryons`
  Edge Function on a daily 02:30 IST `pg_cron` schedule, unless explicitly
  saved to the lookbook. See `docs/dpdp-compliance.md`.

---

## 5. Secrets management

| Item | Location | Tracked in git? |
|---|---|---|
| `GEMINI_API_KEY` | `ipad/Boutique360/Configuration/Secrets.xcconfig` | ❌ gitignored — verified: `git ls-files` returns only `Secrets.xcconfig.example` |
| Supabase URL + anon key | `Env.xcconfig` | ✅ tracked, and safe to ship — the anon key is RLS-protected by design |
| SendGrid / Twilio / Razorpay credentials | `Secrets.xcconfig` | ❌ gitignored |

The Gemini key is sent as an `x-goog-api-key` **header**, never a URL query
parameter, because URLs get logged by intermediaries.
Evidence: `Services/GeminiService.swift`.

**Demo sign-in** (`demo@boutique360.test`) is `#if DEBUG`-gated and must not
reach a release build. This is an explicit line item in
`docs/RELEASE_CHECKLIST.md`.

---

## 6. Row-level security

RLS is enabled on every boutique-scoped table, and client queries additionally
pass `.eq("boutique_id", …)` as belt-and-braces.

**A defect was found and fixed during this work, and it is worth recording in
full because the failure mode generalises.** Migrations `0029` (`order_locks`,
`change_orders`) and `0030` (`reminder_log`) were written with policies using
`current_setting('app.boutique_id', true)` — a transaction-local session
variable that **nothing in this codebase ever sets**. Those policies could
never match, so:

- R3's Lock and change-order features were **non-functional in production**
  from the moment they shipped.
- The defect survived my own "live smoke tests" because those ran through the
  Supabase MCP as `service_role`, **which bypasses RLS entirely.**

Fixed by `supabase/migrations/0031_repair_rls_session_var_policies.sql`, which
moves the affected policies to `current_boutique_id()` (a `SECURITY DEFINER`
function keyed on `auth.uid()`), and verified end-to-end with a genuinely
authenticated session.

**Two lessons recorded as standing rules:**

1. **Never verify RLS as `service_role`.** It proves nothing.
2. **A `select` returning `[]` is not a failed-access signal** — a query with
   no matching policy returns HTTP 200 with an empty array, indistinguishable
   from "no rows exist." Probe with an `INSERT`, which returns 403.

A runbook for periodic RLS verification is proposed but **not yet written** —
owner: unassigned. See §9.

---

## 7. Audit trail

Security-relevant role transitions are recorded to `events` with
`actor_type = 'ipad'`: `staff.role_changed`, `staff.unlock_failed`,
`staff.unlock_device_auth`, `staff.pin_set`.
Evidence: `Services/StaffRoleContext.swift`, `Services/EventsService.record`.

Two honest limits:

- **Audit writes are best-effort.** A network failure logs locally and
  continues; the role change still happens. Blocking a hand-over on a failed
  audit write would be the wrong trade with a customer standing at the
  counter, but it does mean the audit log is not a complete record.
- The audit log lives in the same database the app authenticates to with one
  shared account, so it is **not tamper-evident** against the threat actor in
  §1.

---

## 8. Dependencies

Supabase Swift SDK is the only third-party runtime dependency. Everything
added by R4a/R4b uses system frameworks only — CryptoKit, LocalAuthentication,
Security — deliberately, to avoid expanding the supply-chain surface.

**No automated dependency scanning** (no Dependabot, no SCA in CI) — declared
gap, owner: unassigned.

---

## 9. Declared gaps

Stated plainly rather than papered over. Each needs an owner before release.

| Gap | Impact | Owner |
|---|---|---|
| Server-side RBAC (per-staff accounts + RLS on role) | Role gate is UI-only (§1) | deferred, future release |
| Certificate pinning | MITM not mitigated beyond TLS | unassigned |
| Automated dependency scanning | Vulnerable transitive dep could go unnoticed | unassigned |
| Escalating lockout durations | Brute-force window wider than ideal | deferred (YAGNI at pilot scale) |
| Tamper-evident audit log | Audit not trustworthy against §1 actor | deferred |
| RLS verification runbook | The §6 defect class could recur undetected | unassigned |
| R4b manual QA (9 steps) not executed | Persistence of the role gate across force-quit is **unverified on device** | blocked on Xcode simulator setup |

**On the missing migrations — RESOLVED 2026-07-31.** All 35 applied
migrations are now in `supabase/migrations/`. The nine that existed only in the
remote database were backfilled verbatim from
`supabase_migrations.schema_migrations`, each with a header marking it a record
of SQL that has already run rather than a migration to apply. Files `0025a`–
`0025d` slot between 0025 and 0026 because renumbering already-shipped files
would be worse than a suffix.

Backfilling surfaced two defects that had been invisible while the SQL lived
only in the dashboard — see §11.

---

## 10. What this review did not cover

- No penetration testing, no fuzzing, no static analysis tooling.
- No review of the Supabase project's dashboard access controls or who holds
  the service-role key.
- The Edge Functions (`purge-expired-tryons`, `job-card-view`) were not
  re-reviewed in this pass; `job-card-view` serves an unauthenticated
  token-scoped page to karigars and deserves its own focused review.
- **The nine manual QA steps for R4b have not been run** (see §9), so the
  claim "the role gate survives a force-quit" rests on unit tests of the
  persistence primitives plus code reading, not on observed device behaviour.

---

## 11. Defects surfaced by the migration backfill (2026-07-31)

Two live problems that had been invisible for two months because the SQL
existed only in the Supabase dashboard, where nobody diffs it.

### 11.1 The AI cost ceiling blocks every AI call — **all AI features are down**

`ai_usage_daily` was created with RLS enabled and a **SELECT policy only**,
while `record_ai_usage` is declared `security invoker`. So the function's
INSERT runs as the authenticated user against a table with no INSERT policy.

**Verified as the authenticated demo user (not via MCP, which bypasses RLS):**

```
POST /rest/v1/rpc/record_ai_usage  →  HTTP 403
{"code":"42501","message":"new row violates row-level security policy
                           for table \"ai_usage_daily\""}
```

`ai_usage_daily` contains **zero rows** — the counter has never recorded a
single call since it was created on 2026-05-28.

**Impact.** `AICostMeter.checkCeiling` runs *before* every Gemini request, so
every AI feature fails: design render, virtual try-on, the Hinglish tailor
brief, and style suggestions — the product's core differentiator.

**The error message makes it worse.** `checkCeiling` catches *any* error from
the RPC and rethrows a fixed string:

> "Daily AI cost ceiling reached — try again after midnight or raise the cap
> in Settings."

So the owner is told they have hit a spending cap they have never reached, and
advised to wait until midnight, which changes nothing. A catch-all that
translates every failure into one specific diagnosis is worse than no message.

**Root cause** is identical to the dead policies repaired by 0031: an RLS
policy set that was never exercised as an authenticated user. This is the
third instance. The correct pattern already existed in this codebase two
migrations earlier — `next_sequence_value` in 0022 is `security definer` with
a pinned `search_path` and an explicit grant.

**Proposed fix (not yet applied — needs approval, it is a production schema
change):** make `record_ai_usage` `security definer` with
`set search_path = public, pg_temp`, and validate
`p_boutique_id = current_boutique_id()` inside the function. Adding INSERT and
UPDATE policies instead would work but would defeat the feature's stated
purpose — the doc comment says the counter is "tamper-proof from the iPad",
and a client with UPDATE rights on `ai_usage_daily` could simply zero its own
counter. `security definer` keeps writes exclusive to the function.

Separately, `AICostMeter.checkCeiling` should distinguish a genuine cap breach
(Postgres error code `P0001`) from any other failure.

### 11.2 Production is running on a placeholder GSTIN

Migration `0023_boutique_invoice_fields` seeded a placeholder GSTIN and
address onto the pilot boutique. Checked 2026-07-31 — they are still there:

| Field | Live value |
|---|---|
| `gstin` | `07AAAAA0000A1Z5` (dummy: `AAAAA0000A` PAN pattern) |
| `address` | `Shop 12, Lajpat Nagar, New Delhi 110024` |
| `place_of_supply` | `Delhi` |

Because the app treats a non-empty GSTIN as "invoicing enabled", **any GST
invoice generated today carries a fabricated GSTIN and a placeholder address**
on a statutory tax document. The `coalesce` in the migration means a real
value entered in Settings is never overwritten — but nobody has entered one.

**Action required by the owner, not by code:** enter the real GSTIN, address
and place of supply in Settings → Boutique before issuing another invoice, and
check whether any invoice already sent to a customer needs reissuing.
