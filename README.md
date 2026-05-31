# Boutique 360

iPad-native designer workflow + (planned) web admin + (planned) public storefront for a single boutique business in India. Currently in pilot stage with the iPad app fully functional against a live Supabase backend.

## Documentation

| Doc | What it covers |
|---|---|
| [docs/user-journeys.md](docs/user-journeys.md) | Day-in-the-life scenarios — 8 journeys grounded in the actual boutique owner persona |
| [docs/user-flows.md](docs/user-flows.md) | Mermaid diagrams for auth, magic moment, status updates, error surfacing, DPDP lifecycle, etc. |
| [docs/architecture.md](docs/architecture.md) | Stack, module map, core design rules (signed URL discipline, RPC atomicity, RLS belt-and-braces, error pipeline) + Service catalogue table |
| [docs/architecture-diagrams.md](docs/architecture-diagrams.md) | C4 model — System Context, Container, Component diagrams (Mermaid) |
| [docs/adr/](docs/adr/) | Architecture Decision Records — *why* the foundational choices (5 ADRs) |
| [docs/observability.md](docs/observability.md) | Logging, metrics, alerting plan + what's shipped vs deferred |
| [docs/testing-guide.md](docs/testing-guide.md) | How to run + add unit tests; what we test and (deliberately) don't |
| [docs/runbooks/](docs/runbooks/) | Operational playbooks (bad-deploy rollback, Gemini outage, multi-tenant onboarding) |
| [docs/privacy-policy.md](docs/privacy-policy.md) | DPDP-compliant customer-facing policy (ready for App Store once boutique-specific details filled) |
| [docs/deployment.md](docs/deployment.md) | Environments, schema change workflow, Edge Function deploy, TestFlight, monitoring |
| [docs/dpdp-compliance.md](docs/dpdp-compliance.md) | DPDP Act 2023 posture: what we collect, legal basis, retention, security controls, known gaps |
| [docs/api-rpcs.md](docs/api-rpcs.md) | Postgres RPC reference (`create_order_with_items`, `next_sequence_value`, etc.) |
| [CHANGELOG.md](CHANGELOG.md) | Notable changes per release |
| [audit-outputs/audit-2026-05-26.md](audit-outputs/audit-2026-05-26.md) | Comprehensive whole-codebase audit + fixes applied |
| `docs/superpowers/specs/` | Original design specs |
| `docs/superpowers/plans/` | Implementation plans (1 backend foundation through 10 launch) |

---

## Surfaces

1. **iPad app** (SwiftUI + PencilKit + PDFKit, iOS 17+) — primary designer surface. Sketch → AI render → virtual try-on → job card → invoice. Currently live, used daily.
2. **Web admin** (Next.js, planned) — back-office CRM, analytics
3. **Public website** (Next.js, planned) — order tracking via magic link, public lookbook, inquiry capture

All three share one Supabase backend.

---

## Backend

**Live cloud Supabase project: `boutique-360` (ap-south-1 Mumbai)**

- Project URL: `https://tdnwdlrkbrtoxjzcgusg.supabase.co`
- Dashboard: https://supabase.com/dashboard/project/tdnwdlrkbrtoxjzcgusg
- **26 migrations applied** (audit-fix cycle complete)
- 32+ tables with RLS
- 9 storage buckets configured
- 1 Edge Function (`purge-expired-tryons`) on daily pg_cron
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
# Edit Secrets.xcconfig and set GEMINI_API_KEY = AIzaSy...
xcodegen generate
open Boutique360.xcodeproj
# Cmd+R to run; add `-auto-demo` launch arg to auto-sign-in as demo
```

See [docs/deployment.md](docs/deployment.md) for full setup.

---

## Testing

Unit tests cover pure logic (formatters, validators, parsers, state machines, design tokens, money math). **118 test cases, all green, ~2 seconds local.**

```bash
cd ipad
xcodegen generate
xcodebuild -project Boutique360.xcodeproj \
    -scheme Boutique360 \
    -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
    test
```

CI runs the same on every PR touching `ipad/**` via `.github/workflows/ipad-tests.yml`.

Test files (all in `ipad/Boutique360Tests/`):

| File | Coverage | Cases |
|---|---|---|
| `ConfigTests` | Env.xcconfig values loaded | 2 |
| `FormattersTests` | INR lakh-grouping, postgres date IST round-trip, ISO 8601 precision | 9 |
| `WhatsAppShareHelperTests` | India phone normalization, URL building, emoji/newline encoding | 13 |
| `GSTINValidatorTests` | Structural pattern, edge cases, case-insensitive, length errors | 11 |
| `CustomerImportServiceTests` | RFC 4180 CSV parsing (quoted commas, escaped quotes, CRLF, booleans) | 13 |
| `GSTReportExporterTests` | RFC 4180 CSV escape (commas, quotes, newlines, Hindi, Hinglish) | 10 |
| `StatusMachineTests` | `OrderStatus.nextOptions` + `InquiryStatus.allowedNext` business rules | 11 |
| `CustomerTimelineEventTests` | Composite ID hashability, Set dedup, icon coverage | 4 |
| `EnumDecodingTests` | Forward-compat decode fallback (unknown DB values → safe default) | 7 |
| `ModelDecodingTests` | `Boutique.defaultGstRate`, `OrderItem.gstRate`, `Order.fulfillmentMethod` | 6 |
| `MoneyTests` | Paise rounding (regression test for L7 balance-drift bug) | 10 |
| `PaymentsServiceModelTests` | Codable shapes returned by Supabase | 5 |
| `ErrorBusTests` | Toast pipeline + Identifiable + replace-on-new-report | 5 |
| `DesignTokensTests` | 8pt grid alignment, HIG animation duration ranges | 12 |

**How to add tests**: see [docs/testing-guide.md](docs/testing-guide.md).

Network/integration tests (against test Supabase project) are not yet written — see the testing guide's "We don't test" section for the rationale.

---

## Plan series

- ✅ **Plan 1** — Backend Foundation
- ✅ **Plan 2** — iPad App Foundation
- ✅ **Plan 3** — iPad CRM Core
- ✅ **Plan 4** — PencilKit sketch canvas
- ✅ **Plan 5** — AI render + VTO ("magic moment")
- ✅ **Audit cycle** — comprehensive review + fixes (see CHANGELOG)
- ⏭️ **Plan 6-7** — Web Admin
- ⏭️ **Plan 8** — Public Website + magic-link order tracking
- ⏭️ **Plan 9-10** — Payments (Razorpay), observability, App Store launch

---

## File layout

```
boutique-360/
├── README.md                      ← this file
├── CHANGELOG.md
├── docs/
│   ├── user-journeys.md
│   ├── user-flows.md
│   ├── architecture.md
│   ├── deployment.md
│   ├── dpdp-compliance.md
│   ├── api-rpcs.md
│   ├── superpowers/specs/         ← original design specs
│   └── superpowers/plans/         ← implementation plans
├── audit-outputs/
│   └── audit-2026-05-26.md
├── supabase/
│   ├── config.toml
│   ├── seed.sql
│   └── migrations/                ← 26 migrations
├── ipad/
│   ├── project.yml                ← XcodeGen spec
│   ├── Boutique360/               ← Swift source
│   └── Boutique360Tests/          ← XCTest cases
├── scripts/                       ← bucket setup, ops
└── .gitignore
```
