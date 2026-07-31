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
| Migrations `0020`–`0024` applied to production but **absent from `supabase/migrations/`** | The repo is not a complete record of the schema; a rebuild from source would not reproduce production | unassigned — see note below |
| R4b manual QA (9 steps) not executed | Persistence of the role gate across force-quit is **unverified on device** | blocked on Xcode simulator setup |

**On the missing migrations:** the database reports **35 applied migrations**;
`supabase/migrations/` contains **26 files**. Nine applied migrations exist
only in the remote database:

| Applied migration | In repo? |
|---|---|
| `0020_rls_subquery_and_staff_bootstrap` | ❌ |
| `0021_week1_operational` | ❌ |
| `0022_storage_paths_and_order_lines` | ❌ |
| `0023_boutique_invoice_fields` | ❌ |
| `0024_job_cards` | ❌ |
| `dpdp_purge_cron` | ❌ |
| `audit_fixes_phase2` | ❌ |
| `order_rpc_gst_rate` | ❌ |
| `audit_phase3_constraints_costceil` | ❌ |

This is primarily a disaster-recovery and reproducibility problem: the repo
cannot rebuild production. But one entry raises it above housekeeping —
**`dpdp_purge_cron` is the 7-day VTO photo purge schedule**, a control this
project relies on for DPDP Act compliance and describes in
`docs/dpdp-compliance.md` and the privacy policy. **Its definition is not in
source control**, so it cannot be reviewed in a diff, cannot be restored from
the repo, and could be altered or dropped in the dashboard without any trace
in git. **Purge health — verified during this review (2026-07-31):** the job exists,
is active, and is working. `cron.job` shows `dpdp-purge-tryons`
(`active = true`); `cron.job_run_details` shows **64 runs, all `succeeded`,
most recent 2026-07-30 21:30 UTC**. So the control is operating — it is the
*definition* that is unversioned, not the behaviour that is broken.

**Documentation defect found while verifying:** the cron schedule is
`30 21 * * *` UTC, which is **03:00 IST — not the 02:30 IST stated in
`CLAUDE.md` and `docs/dpdp-compliance.md`.** Harmless operationally, but a
compliance document that misstates a compliance control's schedule is exactly
the kind of drift this review exists to catch. Corrected in the docs as part
of this change.

One limit on that verification: a `succeeded` cron run proves the Edge
Function was *invoked* and returned cleanly. It does not prove rows and
storage objects were actually deleted. An end-to-end purge test — seed a
try-on dated 8 days ago, confirm it disappears — has **not** been run.

**Recommended action** (not taken in this review): dump the nine migrations
from the remote database into `supabase/migrations/` as backfilled files.

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
