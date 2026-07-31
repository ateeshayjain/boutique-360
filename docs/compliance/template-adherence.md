# Template Adherence Register

**Date:** 2026-07-31
**Covers:** the iPad app and Supabase backend as of commit on
`boutique-360-ipad-app`, after R4a/R4b.

> ## ⚠️ This register is INCOMPLETE, and the gap is structural
>
> The plan for this task calls for a **section-by-section** pass over seven
> documents: the Apple Design Framework, Content & Localization, Documentation,
> Performance & Reliability, Release, and Security & Privacy checklists, plus
> the Testing PDF.
>
> **Those documents were supplied as chat attachments and are not in this
> repository.** They are no longer available to the author of this file, so
> the numbered sections cannot be reproduced or mapped against.
>
> Inventing plausible section numbers would produce exactly the artefact this
> register exists to prevent: a compliance document that *looks* authoritative
> and is not traceable to its source. So this file covers what can be verified
> against the code, organised by topic, and every claim names its evidence.
>
> **To complete it:** re-attach the seven documents and the topic findings
> below can be mapped onto their real section numbering. Until then, treat
> the verdicts as accurate and the *coverage* as unproven — there may be
> checklist requirements not represented here at all.
>
> **Owner:** unassigned.

---

## Standing principle recorded from this build

**Copy follows the security rule, not the other way round.**

When UI text and a security control disagreed during R4b, the control won and
the text was rewritten to describe reality. Two instances:

- A `.capped` lockout shows **no countdown**, because nothing is counting
  down. Rendering a timer there would have been friendlier and false.
- `StaffRoleSection`'s footer says assistant mode "hides payments, invoices,
  revenue and settings on this screen. It doesn't restrict the account
  itself" — deliberately deflating, because the honest description of the
  control is weaker than its name implies.

The inverse — softening a control so existing copy stays true — was not done
anywhere in this build.

---

## Security & Privacy

Fully covered in **`SECURITY_REVIEW.md`**, which is the authoritative document
and is not duplicated here. Summary of verdicts:

| Area | Verdict | Evidence |
|---|---|---|
| Credential storage (PIN) | ✅ | `Utilities/PinHasher.swift`; salted SHA-256, constant-time, `ThisDeviceOnly` |
| Secrets not in git | ✅ | `git ls-files` returns only `Secrets.xcconfig.example` |
| API keys in headers, not URLs | ✅ | `Services/GeminiService.swift:172,203` |
| RLS on boutique-scoped tables | ⚠️ | Enabled everywhere, but three tables shipped with dead policies — repaired by migration 0031. See `SECURITY_REVIEW.md` §6 |
| Audit trail for role changes | ⚠️ | Present, but best-effort and not tamper-evident |
| Role-based access control | ❌ | **UI boundary only, not authorization.** `SECURITY_REVIEW.md` §1 |
| Certificate pinning | ❌ | Not implemented. Owner: unassigned |
| Automated dependency scanning | ❌ | No Dependabot/SCA. Owner: unassigned |
| Escalating lockout | ❌ | Deferred (YAGNI at pilot scale) — recorded, not hidden |
| Data residency | ✅ | Supabase ap-south-1 (Mumbai) |
| DPDP 7-day photo purge | ⚠️ | Cron verified running (64 runs, all succeeded); **end-to-end deletion never tested**; definition not in source control |

---

## Content & Localization

| Item | Verdict | Evidence |
|---|---|---|
| Action verbs on buttons | ✅ | "Send on WhatsApp", "Mark done", "Hand over to assistant" |
| Correct plural forms (never "reminder(s)") | ✅ | `RemindersSectionView` computes real singular/plural |
| Error copy names the problem, never the value | ✅ | `PinEntrySheet.copy(for:)` never echoes the PIN |
| Distinct copy per state (loading / empty / error) | ✅ | `RemindersSectionView` has all three |
| Copy does not overstate a control | ✅ | See standing principle above |
| **i18n — String Catalog / `.stringsdict`** | ❌ | **Zero** `.xcstrings`/`.strings`/`.stringsdict` files; all copy is inline English literals. Declared gap. Owner: unassigned |

The i18n gap is worth being precise about: the app ships **Romanized Hindi
(Hinglish)** content for karigars, but as hardcoded English-alphabet strings,
not as a localization. There is no language switch and no plural-rule support
for a second language. Retrofitting this is a large, mechanical change across
~110 Swift files.

---

## Apple Design

| Item | Verdict | Evidence |
|---|---|---|
| Design tokens, no magic numbers | ✅ | `Utilities/DesignTokens.swift`; R4b UI uses `Spacing.medium`, `CornerRadius.chip` |
| Semantic colors (no hardcoded hex) | ✅ | `.orange`, `.red`, `.green`, `.accentColor` throughout |
| ≥44pt touch targets | ✅ | `.frame(minHeight: 44)` on every R4a/R4b control |
| Accessibility labels on composite rows | ⚠️ | 14 of ~40 Feature files. Present on the newest surfaces; **older screens not audited** |
| Role state unambiguous | ✅ | Persistent sidebar badge in assistant mode (`AppShellView`) |
| Dynamic Type | ⚠️ | Text styles used nearly everywhere; **2 fixed-size exceptions** — `DesignsListView.swift:159` and `AppShellView.swift:105`, both decorative empty-state glyphs (acceptable, but they are exceptions) |
| Reduce Motion respected | ⚠️ | Only 2 files reference `accessibilityReduceMotion`; not systematically audited |

---

## Testing

| Item | Verdict | Evidence |
|---|---|---|
| Automated suite green | ✅ | **220 tests, 0 failures** |
| CI runs tests on PR + push to main | ✅ | `.github/workflows/ipad-tests.yml`, `macos-15` |
| Pure-logic engines unit-tested | ✅ | `OrderSlack`, `MorningBoard`, `LockGate`, `CustomerSpend`, `ReminderDrafts`, `PinPolicy`, `RolePolicy`, `PinHasher` |
| Adversarial/edge-case tests | ✅ | Clock-winding, cap precedence, malformed hash blobs, degraded-input suppression |
| **UI / integration tests** | ❌ | None. No XCUITest target. Gating logic is verified by reading, not by driving the UI |
| **Manual QA for R4b** | ❌ | **Nine steps defined, none run** — blocked on local Xcode simulator selection. STOP item in `docs/RELEASE_CHECKLIST.md` §6 |
| Network/integration tests | ❌ | Deferred pending a test Supabase project (documented in the CI workflow header) |

The honest shape of this row: the *pure logic* is well tested, and the
*wiring* is not tested at all. `RolePolicy.canSee` is proven correct; that it
is actually consulted on all 17 gated surfaces rests on a manual audit
(recorded in commit `9eb3223`), not on a test that would fail if someone
deleted a gate.

---

## Documentation

| Item | Verdict | Evidence |
|---|---|---|
| README, architecture, ADRs | ✅ | `README.md`, `docs/architecture.md`, `docs/adr/` |
| Agent briefing kept current | ✅ | `CLAUDE.md` — counts and speed-dial refreshed in this change |
| Runbooks | ⚠️ | Bad-deploy, Gemini-outage, multi-tenant onboarding exist; **no RLS-verification runbook** despite the §6 defect. Owner: unassigned |
| Changelog | ✅ | `CHANGELOG.md` |
| Privacy policy | ⚠️ | Refreshed this change; **still has placeholder operator name, GSTIN, contact, effective date** |
| **LICENSE** | ✅ | Proprietary / all-rights-reserved, © 2026 Ateeshay Jain |
| Release process | ✅ | `docs/RELEASE_CHECKLIST.md` |
| Store disclosure answers | ✅ | `docs/DATA_HANDLING.md` |

---

## Performance & Reliability

| Item | Verdict | Evidence |
|---|---|---|
| Errors surfaced, never silently swallowed | ✅ | Load paths set `loadError` + banner + Retry; the systemic `try?` anti-pattern was fixed in an earlier audit |
| Honest degradation over false data | ✅ | `MorningBoard` renders "—" for failed inputs and real zeros for empty data; `ReminderDrafts` suppresses on degraded input rather than drafting a wrong message |
| Money never derived from a failed fetch | ✅ | `PaymentsSectionView` blocks Record-payment while `loadError != nil` |
| Atomic multi-row writes | ✅ | `create_order_with_items`, `lock_order`, `apply_change_order` RPCs |
| Race-safe sequence numbers | ✅ | `next_sequence_value` RPC |
| **Performance profiling** | ❌ | No Instruments pass, no measured launch time or scroll performance. Owner: unassigned |
| **Crash reporting** | ❌ | No crash reporter integrated; `os.Logger` only, nothing leaves the device |

---

## Release

Covered by `docs/RELEASE_CHECKLIST.md`. Blocking items outstanding:

| Item | Verdict |
|---|---|
| Demo sign-in `#if DEBUG`-gated | ✅ verified at `SignInView.swift:95,120` — **must still be confirmed in a Release build** |
| Version bump process documented | ✅ |
| Rollback path documented | ✅ — and honestly, migrations have **no** rollback |
| **App Store assets** (icon set, screenshots, description, keywords) | ❌ **Not started.** Owner: unassigned |
| **Privacy policy hosted at a public URL** | ❌ Required by both stores |
| Migrations in source control | ❌ Nine applied migrations missing (`SECURITY_REVIEW.md` §9) |

---

## Summary of ❌ / ⚠️ with owners

| Gap | Severity | Owner |
|---|---|---|
| R4b manual QA not run | **Blocks R4b release** | blocked on `sudo xcode-select` |
| App Store assets not started | Blocks release | unassigned |
| Privacy policy placeholders + no public URL | Blocks release | unassigned |
| Nine migrations missing from repo (incl. `dpdp_purge_cron`) | High — no reproducible schema | unassigned |
| Server-side RBAC | High — role gate is UI-only | deferred, future release |
| No UI/integration tests | Medium — gating wiring untested | unassigned |
| End-to-end purge test never run | Medium — DPDP control unproven | unassigned |
| No RLS-verification runbook | Medium — §6 defect class can recur | unassigned |
| No dependency scanning | Medium | unassigned |
| No certificate pinning | Medium | unassigned |
| No crash reporting / perf profiling | Medium | unassigned |
| i18n String Catalog | Low at pilot scale | unassigned |
| Accessibility audit incomplete on older screens | Low | unassigned |
| Escalating lockout | Low (deliberate) | deferred |
| Tamper-evident audit log | Low (deliberate) | deferred |

**Nothing in this register is marked ✅ on the strength of intent.** Where a
control exists but is unproven, it is ⚠️; where it does not exist, it is ❌,
including for items whose absence is a considered decision.
