# Boutique 360

**iPad-native CRM + AI design studio for a designer boutique in India.** One
object — the *Look* — carried from inspiration to delivery: reference photo or
Apple Pencil sketch → fabric → photoreal AI render → virtual try-on → order →
Hinglish job card for the karigar → GST invoice → lookbook. In pilot, used
daily against a live Supabase backend.

**Strategy (July 2026):** iPad-native is the product, not a phase. The Indian
tailoring-CRM market is crowded (Darzee, Boutique Page, Darzi AI — see
[competitive teardown](docs/competitive/darzi-ai-teardown.md)) and the CRM
layer is commoditized. The defensible ground is the **design studio + the Look
lifecycle** — Pencil sketching, fabric draping, and a try-on that shows a
garment that doesn't exist yet. Web surfaces (admin, storefront) are retired
from the roadmap; a customer-facing magic-link order page remains a possible
future, but no owner-facing web app.

## Documentation

| Doc | What it covers |
|---|---|
| [docs/app-map.md](docs/app-map.md) | **Screen-by-screen map** — 45 view files, journeys, department hats, integrations, data spine, roadmap |
| [docs/customer-journey-3-month.md](docs/customer-journey-3-month.md) | The "Priya" journey — 4 orders, varied lifecycles, lessons → backlog |
| [docs/competitive/darzi-ai-teardown.md](docs/competitive/darzi-ai-teardown.md) | Teardown of the closest competitor; threats to absorb + confirmed moat |
| [docs/spec-gaps-waves-1-6.md](docs/spec-gaps-waves-1-6.md) | The 6-wave spec-coverage build (address/WA#, spend report, Email/SMS, Razorpay, templates, AI suggestions) |
| [docs/user-journeys.md](docs/user-journeys.md) | Day-in-the-life scenarios — 8 journeys grounded in the owner persona |
| [docs/user-flows.md](docs/user-flows.md) | Mermaid diagrams — auth, magic moment, status updates, DPDP lifecycle |
| [docs/architecture.md](docs/architecture.md) | Stack, module map, Service catalogue, **the pure-logic core**, 8 core design rules |
| [docs/architecture-diagrams.md](docs/architecture-diagrams.md) | C4 model diagrams |
| [docs/adr/](docs/adr/) | Architecture Decision Records (5) — *why* the foundational choices |
| [docs/observability.md](docs/observability.md) | Logging, metrics, alerting — shipped vs deferred |
| [docs/testing-guide.md](docs/testing-guide.md) | How to run + add tests; what we deliberately don't test |
| [docs/runbooks/](docs/runbooks/) | Bad-deploy rollback, Gemini outage, multi-tenant onboarding |
| [SECURITY_REVIEW.md](SECURITY_REVIEW.md) | **Security posture + threat model + declared gaps** (dated pass, 2026-07-31) |
| [docs/compliance/template-adherence.md](docs/compliance/template-adherence.md) | Section-by-section verdicts against the seven quality checklists |
| [docs/DATA_HANDLING.md](docs/DATA_HANDLING.md) | App Store / Play data-disclosure answers, grounded in real flows |
| [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md) | Cut a release top-to-bottom; rollback paths |
| [docs/privacy-policy.md](docs/privacy-policy.md) | DPDP-compliant customer-facing policy |
| [docs/deployment.md](docs/deployment.md) | Environments, schema workflow, Edge Functions, TestFlight |
| [docs/dpdp-compliance.md](docs/dpdp-compliance.md) | DPDP Act 2023 posture |
| [docs/api-rpcs.md](docs/api-rpcs.md) | Postgres RPC reference |
| [CHANGELOG.md](CHANGELOG.md) | Notable changes per release |
| `docs/superpowers/specs/` + `plans/` | Original design specs + implementation plans |

---

## The product

**One surface: the iPad app** (SwiftUI + PencilKit + PDFKit, iOS 17+).
Consultation-table UX — the selling moment happens across a table with the
customer, not at a desk after she leaves.

The Look lifecycle (see app-map §7): discover → design → try-on → **lock**
(fabric code, measurement version, price, event-date plan, advance) → make →
trial ⟲ alter → deliver → lookbook → repeat sale.

Key-gated integrations (inert until keys in gitignored `Secrets.xcconfig`;
status visible in Settings → Integrations): Gemini AI · SendGrid email ·
Twilio SMS · Razorpay payment links. WhatsApp via `wa.me` links always works.

---

## Backend

**Live cloud Supabase project: `boutique-360` (ap-south-1 Mumbai)**

- Project URL: `https://tdnwdlrkbrtoxjzcgusg.supabase.co`
- Dashboard: https://supabase.com/dashboard/project/tdnwdlrkbrtoxjzcgusg
- **35 migrations applied**, all 35 in source control · 40 tables, RLS on every one · 11 storage buckets
- 2 Edge Functions: `purge-expired-tryons` (daily pg_cron DPDP purge) · `job-card-view` (karigar magic-link page, R4d)
- Seed: 1 boutique ("Aditi Designer Studio") + 3 loyalty tiers

### Smoke test

```bash
# Public, read-only — should return the seeded loyalty tiers
curl "${SUPABASE_URL}/rest/v1/loyalty_tiers?select=name,sort_order&order=sort_order" \
  -H "apikey: ${SUPABASE_ANON_KEY}"
```

---

## Quick start (iPad)

```bash
brew install xcodegen
cd ipad
cp Boutique360/Configuration/Secrets.xcconfig.example Boutique360/Configuration/Secrets.xcconfig
# Edit Secrets.xcconfig — GEMINI_API_KEY required for AI; SendGrid/Twilio/Razorpay optional
xcodegen generate
open Boutique360.xcodeproj
# Cmd+R to run. DEBUG-only launch args: `-auto-demo` (auto-sign-in as demo),
#   `-start-section <name>` (land on a tab other than dashboard)
```

See [docs/deployment.md](docs/deployment.md) for full setup.

---

## Testing

Unit tests cover pure logic (formatters, validators, parsers, state machines,
money math, spend aggregation, phone normalization) plus the decision engines
— slack, morning board, lock gate, reminder drafts, PIN policy, role policy,
AI safety. **239 test cases, all green.**

Measured 2026-08-01: **~2 seconds warm** — execution only, with the simulator
already booted. A **cold** run (clean build + simulator boot) takes ~5 min of
test time and ~13 min wall; nearly all of that is build and launch, not tests.
Scope with `-only-testing:Boutique360Tests/<Suite>` while iterating.

```bash
cd ipad
xcodegen generate
xcodebuild -project Boutique360.xcodeproj \
    -scheme Boutique360 \
    -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
    test
```

CI runs the same on every PR touching `ipad/**` via `.github/workflows/ipad-tests.yml`.
**How to add tests**: [docs/testing-guide.md](docs/testing-guide.md).

---

## Roadmap (iPad-native, competitive-informed)

Sequenced in [docs/app-map.md §7](docs/app-map.md); rationale in the
[journey doc](docs/customer-journey-3-month.md) and
[teardown](docs/competitive/darzi-ai-teardown.md).

- ✅ Plans 1–5 — backend, app foundation, CRM core, sketch canvas, AI render + VTO
- ✅ Audit cycle + spec-gap Waves 1–6
- ✅ **R1 — `event_date` + slack engine** — shipped July 2026 (OrderSlack verdicts, must-finish-by warning, badges)
- ✅ **R2 — exception-first morning board** — shipped July 2026 (tiles + needs-you + pipeline, honest degradation)
- ✅ **R3 — Lock screen** — shipped July 2026 (lock_order + apply_change_order RPCs, LockSheet, append-only CO ledger)
- ✅ **R4 — competitive absorbs** — all four shipped July 2026:
  - ✅ **R4a** auto-drafted reminders with one-tap approve (`ReminderDrafts` engine, `reminder_log` idempotency)
  - ✅ **R4b** owner/assistant roles (hashed PIN, persisted lockout + device-auth escape, 17 gated surfaces) — **a same-device UI boundary, not authorization**; see [SECURITY_REVIEW.md](SECURITY_REVIEW.md) §1
  - ✅ **R4c** fabric-meters estimate in the Hinglish brief
  - ✅ **R4d** karigar phone link (`job-card-view` Edge Function)
- ⏭️ **R5 — fabric inventory** (bolts, codes, meters in/out → fills the "Fabrics" sidebar slot)
- ⏭️ **R6 — karigar ledger** (material issued, piece-rate dues, alteration-rate quality metric)
- ⏭️ TestFlight → App Store

---

## File layout

```
boutique-360/
├── README.md                      ← this file
├── CHANGELOG.md · CLAUDE.md · LICENSE · SECURITY_REVIEW.md
├── docs/                          ← see Documentation table above
│   └── competitive/               ← market teardowns
├── audit-outputs/
├── supabase/
│   ├── config.toml · seed.sql
│   └── migrations/                ← 35 files, 35 applied (backfilled 2026-07-31)
├── ipad/
│   ├── project.yml                ← XcodeGen spec (source of truth)
│   ├── Boutique360/               ← Swift source (Features / Services / Models / Utilities)
│   └── Boutique360Tests/          ← 239 XCTest cases (28 files)
├── scripts/
└── .gitignore
```
