# Boutique 360

iPad-native designer workflow + web admin CRM + public storefront for boutique businesses.

- **Spec (web):** `docs/superpowers/specs/2026-05-25-boutique-360-design.md`
- **Spec (iPad addendum):** `docs/superpowers/specs/2026-05-25-boutique-360-ipad-addendum.md`
- **Plans:** `docs/superpowers/plans/`

## Surfaces

1. **iPad app** (SwiftUI + PencilKit) — primary designer surface, in-store use, AI sketch→render→VTO workflow
2. **Web admin** (Next.js, later) — back-office CRM, automation, analytics
3. **Public website** (Next.js, later) — catalog, inquiries, order tracking, checkout for ready-to-ship items

All three share one Supabase backend.

## Backend status

**Live cloud Supabase project: `boutique-360` (ap-south-1 Mumbai)**

- Project URL: `https://tdnwdlrkbrtoxjzcgusg.supabase.co`
- Dashboard: https://supabase.com/dashboard/project/tdnwdlrkbrtoxjzcgusg
- 19 migrations applied (Plan 1 complete)
- 31 tables created with RLS
- 9 storage buckets configured
- Seed: 1 boutique ("Aditi Designer Studio") + 3 loyalty tiers (Silver/Gold/Platinum)

### Quick verify

```bash
# Public, read-only — should return the seeded boutique
curl "${SUPABASE_URL}/rest/v1/loyalty_tiers?select=name,sort_order&order=sort_order" \
  -H "apikey: ${SUPABASE_ANON_KEY}"
```

Returns: `[{"name":"Silver","sort_order":1},{"name":"Gold","sort_order":2},{"name":"Platinum","sort_order":3}]`

(Note: anon role can read this because `boutique_id` policy isn't set on `loyalty_tiers` for anon — anon must have its own policy added in a future migration if customer-facing tiers display is needed.)

## Plan series

- ✅ **Plan 1** — Backend Foundation (`docs/superpowers/plans/2026-05-25-plan-01-backend-foundation.md`)
- ⏭️ **Plan 2** — iPad App Foundation (Xcode project, SwiftUI scaffold, Supabase Swift SDK, auth)
- ⏭️ **Plan 3** — iPad Design Canvas (PencilKit, fabric attach, measurements)
- ⏭️ **Plan 4** — iPad AI Pipeline (Gemini sketch→render, VTO)
- ⏭️ **Plan 5** — iPad CRM + Catalog
- ⏭️ **Plan 6-7** — Web Admin
- ⏭️ **Plan 8** — Public Website + Automation/Messaging
- ⏭️ **Plan 9-10** — Payments, observability, deploy

## Local dev setup (when web Plans start)

Supabase CLI is initialized in `supabase/`, but we use the cloud project as the source of truth. Local dev requires Docker for `supabase start`. For now, just `.env.local` against the cloud project.

```bash
cp .env.example .env.local
# Fill in SUPABASE_SERVICE_ROLE_KEY from https://supabase.com/dashboard/project/tdnwdlrkbrtoxjzcgusg/settings/api
```

## File layout

```
boutique-360/
├── docs/superpowers/specs/    # design specs (committed)
├── docs/superpowers/plans/    # implementation plans (committed)
├── supabase/
│   ├── config.toml
│   ├── seed.sql
│   └── migrations/            # 19 migrations (Plan 1)
├── scripts/                   # bucket creation + other ops scripts
├── .env.example
├── .gitignore
└── README.md
```
