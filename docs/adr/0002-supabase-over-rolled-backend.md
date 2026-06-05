# ADR 0002 — Supabase as the only backend instead of rolling our own

**Date:** 2026-05-25
**Status:** Accepted

---

## Context

Boutique 360 needs:
- Auth (the boutique owner signs in once per device)
- Postgres database with multi-tenant isolation (one boutique today, possibly many tomorrow)
- File storage with private/public buckets (sketches, AI renders, VTO photos)
- Real-time subscriptions (future: live order updates when web admin ships)
- Edge Functions (the DPDP photo-purge cron lives here)
- ap-south-1 region availability (DPDP cross-border concerns + latency)

Alternatives:
1. **Roll our own** — Postgres on a managed host (RDS / Cloud SQL) + S3 + Cognito or Auth0 + Lambda or Cloud Run
2. **Firebase** — Google's BaaS
3. **AWS Amplify** — wraps the AWS-native services with a SDK
4. **Supabase** — Postgres-first BaaS, open-source, Mumbai region available

---

## Decision

Use **Supabase Cloud** as the sole backend, in the **ap-south-1 Mumbai region**. The cloud project is `tdnwdlrkbrtoxjzcgusg`.

Adopt:
- Supabase Auth (magic link — see ADR 0004)
- Supabase Postgres with RLS policies for multi-tenant isolation
- Supabase Storage with private buckets for sensitive assets + public for watermarked VTO results
- Supabase Edge Functions for scheduled jobs (`purge-expired-tryons`)
- `pg_cron` extension for scheduling

---

## Consequences

### What becomes easier
- **One vendor relationship** instead of 4-5 (auth, DB, storage, functions, scheduler)
- **RLS as the multi-tenant boundary** — defined in SQL, enforced by Postgres, can't be bypassed by a forgotten check in application code
- **Postgres-native** — full SQL, real foreign keys, real transactions, real indexes. We use `jsonb_populate_record` in `create_order_with_items` RPC — that's not available on Firestore.
- **Mumbai region** — DPDP data stays in India by default, latency from Tier-1 Indian cities is <50ms
- **Generated TypeScript types** for future web admin — `supabase gen types` will let the Next.js app share the schema
- **Cheap to start** — free tier covers the pilot; Pro tier is $25/mo when storage > 1GB or function invocations > 500k/mo

### What becomes harder
- **Vendor lock-in is partial** — RLS policies and `pg_cron` jobs are Postgres-portable; Edge Functions are Supabase-specific (Deno + their runtime hooks); Auth tokens are Supabase JWTs (we'd need to re-issue on migration)
- **Operational visibility is via their dashboard** — no direct access to underlying RDS / EC2 / Cloudwatch
- **Free-tier limits** — auto-pause after 7 days inactivity on Free; pilot uses Pro
- **No multi-region failover** — if Mumbai goes down, we're down. Acceptable for pilot.

### What becomes impossible (without migration)
- **Sub-millisecond reads at scale** that would require a custom Postgres setup with read replicas in multiple regions. Not in scope for pilot.

---

## Alternatives considered

### Roll our own (Postgres + S3 + Cognito + Lambda)
- Pro: full control, no lock-in, every component independently swappable
- Con: 4 services to operate, 4 IAM policies to wire, no built-in RLS pattern. The work to set up + maintain this is days that don't ship features for the boutique.
- **Why rejected:** Boutique 360 is pre-revenue; engineering time saved is more valuable than vendor flexibility we may never need.

### Firebase (Firestore)
- Pro: mature, generous free tier, great for real-time
- Con: NoSQL. Our data is heavily relational (Order ↔ OrderItem ↔ Customer ↔ Boutique). Modeling this in Firestore would require either denormalization (and the sync bugs that come with it) or careful subcollection design that makes server-side joins hard. RLS-equivalent (security rules) is its own DSL — less expressive than Postgres RLS.
- **Why rejected:** GST invoices need transactional joins; the order create RPC needs FK constraints; nothing in Firestore beats Postgres for this shape of data.

### AWS Amplify
- Pro: integrates AWS native services, SDK generates types
- Con: AppSync (GraphQL) is the canonical pattern, adds a layer over the data store. Auth via Cognito is fine but configuration-heavy. Cost projection at scale is much higher than Supabase.
- **Why rejected:** the simplicity-per-dollar ratio favors Supabase for our scale.

### Custom: Postgres + Hasura
- Pro: GraphQL auto-generated, RLS-like permissions
- Con: still two vendors (database + Hasura cloud or self-host), and Hasura is harder to monetize for a small Indian boutique deployment
- **Why rejected:** Supabase gives PostgREST for free which serves the same need at lower complexity

---

## Risks accepted

| Risk | Mitigation |
|---|---|
| Supabase outage takes us fully offline | Documented in `docs/runbooks/` (planned). Pilot acceptable; multi-region failover when revenue justifies |
| Vendor pricing changes | We're locked-in for the data, not the contract. RLS policies + schema are portable to vanilla Postgres in a weekend if needed. |
| Service deprecation (Edge Functions) | Currently we have only one Edge Function — `purge-expired-tryons`. Re-implementing as a `pg_cron`-only solution would be ~1 day if Supabase pivots away from Deno. |

---

## Related

- ADR 0001 — Native iPad (Supabase's Swift SDK is the native-app integration)
- ADR 0004 — Magic-link auth (Supabase Auth feature)
- `docs/deployment.md` — environment + schema workflow
- `docs/dpdp-compliance.md` — Mumbai region + at-rest encryption posture
