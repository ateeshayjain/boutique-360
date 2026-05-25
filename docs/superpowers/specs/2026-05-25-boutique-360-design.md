# Boutique 360 — Design Spec

**Date:** 2026-05-25
**Status:** Draft (awaiting review)
**Owner:** Ateeshay Jain
**Scope:** v1 commercially deployable build for a single paying boutique client.

---

## 1. Goal & Non-Goals

### Goal
Build a commercially deployable Boutique CRM + AI Try-On + Public Website for a single paying boutique client. The system must support **hybrid commerce** (ready-to-ship checkout *and* bespoke inquiry pipeline), be production-grade from day one (real WhatsApp Business API, real payments, real auth, GST-compliant invoicing), and ship within ~4-6 weeks.

### Non-goals (v1)
- Multi-tenant SaaS (schema is forward-compatible via `boutique_id` + RLS, but only one boutique deployed)
- Offline-first POS / barcode hardware integration
- Multi-location / branch filtering (single shop in v1)
- Production / Job Cards / Karigar payroll / Raw Material costing (separate "Workshop OS" slice)
- Customer-facing AI design generation (staff-only in v1; schema forward-compatible)
- Native mobile apps (responsive web only)
- Multi-language UI (English + Hindi/Hinglish content via CMS only)

### Out of scope, but referenced
- The three existing forks (`Boutique360 (1)`, `Boutique360 (2)`, `boutique-360`) are **reference material only**. We are not merging or porting — we are building fresh on a new stack chosen for commercial deployability.

---

## 2. Constraints & Assumptions

### Hard constraints
- **Region:** India (INR, GST, DPDP Act, Indian phone format)
- **Channel:** WhatsApp is the primary customer engagement channel (95%+ open rates vs ~15% email)
- **Client readiness:** Meta Business Account + dedicated WhatsApp number + GST cert needed before WhatsApp go-live (1-2 week external dependency)
- **Budget posture:** Solo/small-team build; managed services preferred over self-hosting
- **Compliance:** GST invoicing required; DPDP Act consent capture required; PCI scope avoided (Razorpay Checkout handles cards)

### Assumptions
- ~500 active customers in year 1 (sizing for that, not 50,000)
- Boutique owner is comfortable with web admin (not a CLI-only user)
- VTO and AI design are differentiators, not gimmicks — owner wants them visible
- Indian boutique customers (especially older demographics) prefer magic-link order tracking over account signup

---

## 3. Architecture

### Shape
Single Next.js 15 (App Router) repo deployed on Vercel. Two route groups under one domain serve two distinct audiences:

```
boutique.com/                    ← public storefront (SSR, SEO-indexed)
  /                              home / lookbook
  /shop                          catalog (ready-to-ship + bespoke)
  /shop/[slug]                   product detail + VTO launcher
  /try-on/[productId]            VTO experience
  /inquire/[productId]           bespoke inquiry form
  /cart, /checkout               ready-to-ship only
  /orders/[token]                guest order tracking (magic link)

admin.boutique.com/              ← staff CRM (auth-gated, noindex)
  /dashboard                     today's view
  /customers, /customers/[id]    CRM + 360° profile
  /inquiries                     bespoke kanban
  /orders                        transactional kanban
  /products                      catalog manager
  /design-studio                 AI design generation (staff-only)
  /automation                    journey builder + templates
  /messages                      WhatsApp conversation inbox
  /settings                      branding, integrations, users
```

Both domains route to the same Vercel project. Route group `(public)` and `(admin)` separate concerns at the code level; deploy is unified.

### Service topology

```
┌──────────────────────────────────────────────────┐
│           Next.js (Vercel Edge + Node)           │
│  ─ Public pages (SSR/ISR)                        │
│  ─ Admin pages (CSR + Server Actions)            │
│  ─ /api/webhooks/* (Razorpay, Interakt, Inngest) │
└────────┬───────────┬───────────┬─────────────────┘
         │           │           │
    ┌────▼────┐ ┌────▼────┐ ┌────▼─────────────┐
    │Supabase │ │ Gemini  │ │  Interakt (BSP)  │
    │ ─ Pg+RLS│ │ AI for  │ │  ─ WhatsApp send │
    │ ─ Auth  │ │ VTO &   │ │  ─ Templates     │
    │ ─Storage│ │ design  │ │  ─ Inbound webhk │
    │ ─Realtime│ └─────────┘ └──────────────────┘
    └─────────┘
         │
    ┌────▼────────────┐  ┌──────────────┐  ┌──────────────┐
    │  Razorpay       │  │  Resend      │  │  Inngest     │
    │  (payments)     │  │  (email)     │  │  (job queue) │
    └─────────────────┘  └──────────────┘  └──────────────┘
```

### Key choices
- **Auth:** Supabase Auth, magic-link for staff. RLS policies enforce row-level access scoped by `boutique_id` (forward-compat for multi-tenant). Customers don't get accounts; magic-link order tracking URLs only.
- **Background jobs:** Inngest. Purpose-built for Next.js, step functions, retries with backoff, observability. Sidesteps Vercel function timeouts.
- **Images:** Supabase Storage + Next.js `<Image>` for automatic optimization.
- **Realtime** (admin inbox, kanban updates): Supabase Realtime channels.
- **Type safety:** TypeScript end-to-end with auto-generated types from Supabase schema (`supabase gen types`).

### Why this over alternatives
- **vs two-app split** (admin SPA + public Next.js): defer until past PMF / multi-boutique. One repo = one set of types/components/deploy.
- **vs headless commerce (Medusa/Saleor):** overkill for one client with hybrid (not pure transactional) commerce.
- **vs Cloudflare Workers + D1** (the existing fork stack): D1 maturity + need for auth/storage/realtime would force adding R2, Workers KV, custom auth — by which point we've rebuilt 70% of Supabase.

---

## 4. Data Model (Postgres / Supabase)

Conventions: every table has `id uuid pk default gen_random_uuid()`, `created_at timestamptz`, `updated_at timestamptz` (trigger-maintained), and `boutique_id uuid` (RLS scope).

### People

```sql
customers
  name, phone (unique per boutique), email, dob, address_json,
  tags text[], vip_status bool,
  loyalty_points int default 0, current_tier_id (fk loyalty_tiers nullable),
  source ('walkin'|'website'|'referral'|'instagram'|'imported'),
  consent_whatsapp bool default false, consent_email bool default false,
  lifetime_value_cached numeric default 0,
  email_bounce_count int default 0,
  deleted_at timestamptz   -- soft-delete for DPDP "forget me"

customer_profiles            -- 1:1 with customers
  customer_id (pk, fk),
  style_persona ('traditional'|'fusion'|'modern'|'minimalist'|'maximalist'),
  color_palette text[], fabric_preferences text[], avoid_fabrics text[],
  body_type ('pear'|'apple'|'hourglass'|'rectangle'|'inverted_triangle'),
  height_cm int, skin_tone ('fair'|'wheatish'|'dusky'|'deep'),
  budget_band ('value'|'mid'|'premium'|'luxury'),
  favorite_designers text[], pinterest_url, instagram_handle,
  style_notes_md

customer_measurements
  customer_id, garment_type, measurements_json,
  taken_by (fk staff_users), taken_at timestamptz

customer_relationships
  customer_id, related_customer_id,
  relation ('mother'|'daughter'|'sister'|'spouse'|'friend'|'referrer')

important_dates
  customer_id, occasion ('anniversary'|'kids_bday'|'sangeet'|custom_label),
  date date, recurring bool, reminder_days_before int default 7

staff_users                  -- id = auth.users.id (1:1 with Supabase Auth)
  name, role ('owner'|'manager'|'staff'), phone, active bool default true
```

### Loyalty

```sql
loyalty_tiers
  name, min_lifetime_value numeric, min_orders int,
  points_multiplier numeric default 1.0,
  perks_json,    -- {early_access, free_shipping, birthday_voucher_amount, priority_support}
  color_hex, sort_order

customer_tier_history
  customer_id, tier_id, achieved_at, expired_at (nullable)
```

### Catalog

```sql
products
  sku, name, slug (unique per boutique), description_md, category,
  mode ('ready_to_ship'|'bespoke'|'both'),
  base_price numeric, sale_price numeric, hsn_code, gst_rate numeric,
  hero_image_url, gallery_urls text[],
  vto_enabled bool default false, vto_flat_lay_url,
  published bool default false, seo_title, seo_description,
  created_by (fk staff_users)

product_variants
  product_id, sku, size, color, stock_qty int default 0,
  price_override numeric
```

### Commerce (transactional)

```sql
orders
  order_number text (human, unique), customer_id,
  status ('pending'|'confirmed'|'packed'|'shipped'|'delivered'|'cancelled'|'returned'),
  subtotal, gst_amount, shipping, total numeric, currency text default 'INR',
  shipping_address_json, tracking_url, tracking_courier,
  placed_at timestamptz, magic_link_token text unique

order_items
  order_id, product_id, variant_id, qty int, unit_price numeric, gst_amount numeric

payments
  order_id, razorpay_order_id, razorpay_payment_id (unique),
  amount numeric, status ('created'|'authorized'|'captured'|'failed'|'refunded'),
  method ('upi'|'card'|'netbanking'|'wallet'|'cash'),
  raw_payload_json, captured_at timestamptz

invoices
  order_id (unique), invoice_number text unique, pdf_url,
  gst_breakdown_json, issued_at timestamptz
```

### Bespoke / inquiry (separate lifecycle)

```sql
inquiries
  inquiry_number text unique, customer_id, product_id (nullable),
  status ('new'|'consulting'|'measurements'|'quoted'|'confirmed'|
          'in_production'|'ready'|'delivered'|'lost'),
  occasion, event_date, budget_range, notes,
  assigned_to (fk staff_users), source,
  converted_order_id (fk orders nullable)

inquiry_messages
  inquiry_id, author ('customer'|'staff'), body, attachments_urls text[]
```

### Virtual try-on

```sql
vto_sessions
  customer_id (nullable for anon), product_id,
  user_image_url, result_image_url, model_used,
  processing_ms int, status ('queued'|'done'|'failed'), error_msg,
  cost_estimate_usd numeric,
  viewed_at, converted_to_inquiry_id (nullable)
```

### AI design studio (staff-only v1)

```sql
design_generations
  customer_id (nullable), staff_user_id,
  prompt_text, reference_image_urls text[],
  mode ('pattern'|'garment_design'|'color_variant'|'embellishment_concept'),
  base_product_id (nullable),
  result_image_urls text[],
  model_used ('gemini-2.5-flash-image'|'imagen-3'),
  processing_ms int, cost_estimate_usd numeric,
  status ('queued'|'done'|'failed'),
  parent_generation_id (nullable, fk self),  -- iteration tree
  saved_to_lookbook bool default false,
  converted_to_product_id (nullable, fk products)

design_lookbook
  name, cover_image_url, description,
  visible_to ('staff_only'|'customer_shared'|'public')

lookbook_items
  lookbook_id, design_generation_id (nullable), product_id (nullable),
  sort_order
```

### Messaging

```sql
message_templates
  name, channel ('whatsapp'|'email'|'sms'),
  whatsapp_template_name, whatsapp_template_status ('draft'|'submitted'|'approved'|'rejected'),
  body_template, variables_json, category

conversations
  customer_id, channel, last_message_at, unread_count int, assigned_to

messages
  conversation_id, direction ('out'|'in'), channel,
  template_id (nullable), body, media_urls text[],
  status ('queued'|'sent'|'delivered'|'read'|'failed'),
  provider_message_id (unique per provider), error_msg, sent_at
```

### Automation

```sql
automation_journeys
  name, trigger_event,
    -- 'inquiry.created' | 'order.confirmed' | 'order.shipped'
    -- | 'customer.birthday' | 'customer.dormant_90d'
    -- | 'vto.completed_no_inquiry' | 'important_date.upcoming'
  active bool, steps_json   -- [send_template, wait, branch, send_template, ...]

journey_runs
  journey_id, customer_id, current_step int,
  status ('running'|'completed'|'failed'|'cancelled'),
  started_at, ended_at, last_step_at
```

### Misc

```sql
events
  actor_type ('staff'|'customer'|'system'|'webhook'),
  actor_id (uuid nullable),
  event_name text, payload_json, occurred_at timestamptz
  -- append-only audit log + analytics source

settings
  boutique_id, key text, value_json     -- (boutique_id, key) unique
  -- includes encrypted integration secrets via pgsodium
```

### Key relationships
- `customer` → many `orders`, `inquiries`, `conversations`, `vto_sessions`, `measurements`, `important_dates`
- `inquiry` and `order` are **separate tables, not statuses on one** (different lifecycles, columns, analytics). Bridged by `inquiries.converted_order_id`.
- `messages` is the single source of truth for all customer comms — admin inbox queries this.
- `events` is append-only — every state change writes here.

### Storage buckets
- `product-images` — public, CDN'd
- `vto-uploads` — private, signed URLs, 30-day TTL (auto-purge)
- `vto-results` — public, watermarked
- `design-generations` — private, staff-only
- `invoices` — private, owner-only
- `measurements-photos` — private, staff-only

### RLS posture
- All tables: `boutique_id = current_setting('app.boutique_id')` (set per request from session JWT claim)
- `staff_users.role` gates writes (e.g., only `owner|manager` can edit products, automation, settings)
- Public storefront uses read-only anon key with policies restricting to `products.published = true` (joins to variants/lookbook respected)

### PII encryption
- pgsodium column-level encryption for `customers.dob`, `customer_measurements.measurements_json`
- All other PII (phone, email, address) at-rest-encrypted by Supabase default

---

## 5. Modules

Eleven modules. Each has its own routes, server actions, RLS scope, and test suite.

| # | Module | Routes | Owns |
|---|---|---|---|
| 1 | CRM Core | `/admin/customers`, `/admin/customers/[id]` | customers, profiles, relationships, measurements, important_dates, tier_history |
| 2 | Catalog & Inventory | `/admin/products` | products, variants, product images |
| 3 | Commerce / Orders | `/admin/orders`, `/checkout`, `/orders/[token]` | orders, order_items, payments, invoices |
| 4 | Bespoke Pipeline | `/admin/inquiries`, `/inquire/[productId]` | inquiries, inquiry_messages |
| 5 | Virtual Try-On | `/try-on/[productId]`, `/admin/vto-sessions` | vto_sessions, image pipeline |
| 6 | AI Design Studio | `/admin/design-studio` | design_generations, design_lookbook, lookbook_items |
| 7 | Automation Engine | `/admin/automation` | automation_journeys, journey_runs, message_templates |
| 8 | Messaging Inbox | `/admin/messages` | conversations, messages |
| 9 | Public Website | `/`, `/shop`, `/shop/[slug]` | rendering, SEO, sitemap, OG images |
| 10 | Dashboard | `/admin/dashboard` | read-only views over events, orders, inquiries |
| 11 | Settings | `/admin/settings` | settings, staff_users, encrypted integration creds |

### Module dependency principle
Modules do **not** call each other directly. They emit events into the `events` table; the Automation Engine subscribes via Supabase webhook → fires Inngest functions. Adding a new automation ("thank-you 7 days post-delivery") is a config change, not a code change.

### Notable UX/design calls
- **CRM 360° profile** — left rail: contact + tier + tags. Main: timeline of events. Right rail: open inquiries, recent orders, upcoming dates, VTO/design history. Customer merge tool for dedup on phone.
- **Catalog mode toggle** — `ready_to_ship` enforces stock + cart button; `bespoke` shows only inquire button; `both` shows both CTAs.
- **Orders kanban** — drag-to-transition fires automation events.
- **Bespoke kanban** — `new → consulting → measurements → quoted → confirmed → in_production → ready → delivered/lost`. On `confirmed`, can spawn paired `orders` row via `converted_order_id` bridge.
- **VTO** — async via Inngest (Gemini takes 5-30s). Watermarked output. User upload auto-deleted after 30 days. Anon rate limit: 5/day per IP.
- **Design Studio** — chat-style: prompt + refs → 4 variants → click to iterate → save to lookbook → optional "promote to catalog" creates draft product. Refinement tree visible. Monthly budget cap with auto-disable.
- **Automation builder** — visual: trigger → wait → send template → branch on reply/open. Built-in starter journeys: order confirmation, shipping update, inquiry follow-up (24h if no staff reply), birthday with tier-aware voucher, important-date reminder (N days before), win-back at 90d dormant, post-VTO nudge at 1h if no inquiry.
- **Inbox** — WhatsApp-Business-style: conversation list / thread / customer context panel. Quick-reply templates. 24h-window countdown badge so staff don't miss the free-form window.
- **Public site** — editorial, not Amazon grid. ISR (1hr revalidate), on-demand revalidation on publish. JSON-LD product schema. WhatsApp chat float button deep-links to boutique number.
- **Magic-link order tracking** — instead of customer accounts. Sent via WhatsApp: "track your order: [link]". Token-gated, expires after 90 days.

---

## 6. Integrations

### Interakt (WhatsApp BSP)
- Send template + session messages, receive inbound webhook
- Why over direct Meta: better template UX, Indian support, GST-invoiced (~₹0.80/conversation)
- Setup: client creates Interakt account, links FB Business Manager, verifies WA number (~1-2 weeks). API key stored encrypted in `settings`.
- Templates created in Interakt UI, polled into `message_templates` with status (so UI can show "awaiting Meta approval")
- Failure modes: not-approved template → fallback to email if consented, else queue + alert. Send failure → Inngest retry ×3 + dead-letter. Outside 24h window without template → block + surface in inbox.
- Webhook: `/api/webhooks/interakt`, signature-verified, Realtime push to inbox.

### Razorpay
- UPI Intent + UPI QR + cards + netbanking + wallets for ready-to-ship orders. Refunds via API for cancellations.
- Setup: merchant KYC (~3 days). Keys + webhook secret encrypted in `settings`.
- Flow: `createOrderFromCart()` → Razorpay order → Checkout JS modal → success callback + webhook (idempotent on `razorpay_payment_id`) → `payments` captured → `orders` confirmed → `order.confirmed` event → automation fires WA confirmation + invoice.
- Reconciliation cron (15min) catches missed webhooks (~0.5% in the wild).
- Auto-cancel `pending` orders after 30min.

### Gemini (Google AI)
- `gemini-2.5-flash-image` for VTO + design gen (~$0.04/image)
- `gemini-2.5-flash` for text (descriptions, reply suggestions, inbound intent classification)
- `imagen-3` via Vertex AI as "premium" mode in Design Studio
- Cost guards: per-IP rate limit (5/day anon VTO), monthly boutique-wide budget cap with auto-disable, per-gen cost recorded
- Safety: Gemini Safe Search check before storing user VTO upload; reject NSFW/CSAM

### Resend
- Magic-link login for staff
- Invoice PDFs (attachment + link)
- Order confirmation fallback for non-WhatsApp-consenting customers
- React Email components for brand-matched templates
- Setup: API key + verified sending domain (~30min DNS)

### Inngest
- All async work: automation journeys, VTO/design gens, webhook fan-out, reconciliation crons, tier recompute, birthday/important-date scanners, dormant scanner
- Step functions with `sleep` for multi-day journeys
- All functions idempotent; retries with exponential backoff; dead-letter → Slack alert
- Free tier (50k runs/mo) sufficient

### Secrets management
Two locations only:
1. Vercel env vars: deploy-time secrets (Inngest signing key, Supabase service role)
2. `settings` table (encrypted via pgsodium): owner-rotatable keys (Interakt, Razorpay, Gemini)

Rotating a key never requires a redeploy.

---

## 7. Deployment & Ops

### Environments

| Env | Domain | Supabase | Razorpay | Interakt | Purpose |
|---|---|---|---|---|---|
| local | localhost:3000 | local supabase (Docker) | test | sandbox | dev |
| preview | `pr-N.boutique-360.vercel.app` | shared staging | test | sandbox | per-PR review |
| staging | `staging.boutique.com` | staging | test | sandbox | UAT with client |
| production | `boutique.com` + `admin.boutique.com` | prod | live | live | live |

### CI/CD
- GitHub → Vercel; `main` auto-deploys prod; every PR gets preview deploy + Supabase branch
- Pre-merge: typecheck, lint, vitest (unit), playwright e2e smoke (signup → inquiry → WA send → mark delivered), bundle-size check (250kb soft cap on storefront)
- DB migrations: Supabase CLI, version-controlled SQL in `supabase/migrations/`, applied on deploy

### DNS
- `boutique.com` → Vercel (public, SSR)
- `admin.boutique.com` → same Vercel project, `/admin/*` route group
- `boutique.com/api/webhooks/*` → webhook endpoints
- MX → Resend (transactional) + Google Workspace (boutique's own email)
- SPF/DKIM/DMARC for Resend domain

### Observability

| Concern | Tool |
|---|---|
| Errors | Sentry (frontend + server + Inngest) |
| Logs | Vercel + Supabase native → aggregated to Axiom |
| Uptime | Better Stack (1min ping `/api/health`, public status page) |
| Performance | Vercel Speed Insights + Sentry traces |
| Cost | In-app dashboard widget (AI spend MTD, WA msg counts, Razorpay txn vs cap) |
| WhatsApp health | In-app widget: delivery/read rates by template, failure breakdown |

`/api/health` checks: DB conn, Inngest reachable, Storage reachable, **last `events` timestamp** (catches silent event-bus failures).

### Backups & DR
- Supabase Pro: PITR 7-day + daily backup 30-day retention
- Cross-cloud: nightly sync of `invoices/` and `measurements-photos/` to Cloudflare R2 (different provider, 8-year GST retention safety)
- Settings export: weekly encrypted dump to R2
- RPO: 5min (PITR) DB / 24h cross-cloud assets
- RTO: 1hr full restore

### Security baseline
- Admin routes behind Supabase Auth + middleware (`staff_users.active = true`)
- RLS enforced on every table; service-role key only in trusted server code
- Webhook signature verification on every inbound (Razorpay HMAC, Interakt signature)
- Upstash Ratelimit: storefront lead-capture, VTO request, admin login
- CSP, HSTS, X-Frame-Options DENY on admin
- pgsodium column-level encryption for measurements + DOB
- Audit log via `events`
- GDPR/DPDP: `getMyData(customerId)` export + `forgetMe(customerId)` soft-delete (retains anonymized order records for tax compliance)
- Razorpay webhook IPs allowlisted at Vercel edge
- Image uploads: Gemini Safe Search check before storing user VTO uploads

### Compliance
- **GST:** invoice with GSTIN, HSN, place of supply, tax breakdown. PDF retained 8 years.
- **DPDP Act:** consent at every lead capture, withdrawal flow in profile.
- **PCI:** out of scope (Razorpay Checkout handles cards).
- **WhatsApp commerce policy:** opt-in at every capture, unsubscribe instruction in utility/marketing templates.

### Cost summary (1 boutique, ~500 active customers)

| Item | Monthly |
|---|---|
| Vercel Pro | $20 |
| Supabase Pro | $25 |
| Resend, Inngest, Sentry, Axiom, Better Stack | $0 (free tiers) |
| Cloudflare R2 backup | ~$1 |
| Interakt | ~₹1,500 + per-msg |
| Razorpay | 2% txn fee |
| Gemini API | ~$15 |
| **Subtotal** | **~$60/mo + variable** |

Plus: domain ~$15/yr, one-time legal review of T&Cs/Privacy Policy.

### Rollout
1. Internal dogfood (1 week) — owner uses admin, real catalog, test mode for payments/WA
2. Soft launch (2 weeks) — 10-20 invited customers, live integrations, daily monitoring
3. Public launch — SEO submit, Instagram announcement, ads

---

## 8. Open Questions / Day-One Client Homework

These are blockers for go-live but not for dev to start:

- [ ] Meta Business Account created + FB Page exists
- [ ] Dedicated WhatsApp number (no existing WA account on it)
- [ ] GST cert + business proof for WA verification
- [ ] Razorpay merchant account submitted (KYC ~3 days)
- [ ] Domain registered (`.com` and `.in`)
- [ ] Google Workspace for boutique's own email
- [ ] Brand assets: logo (SVG), color palette, font choice
- [ ] Initial product photography (~20-30 SKUs to launch with)
- [ ] T&Cs + Privacy Policy + Shipping Policy + Returns Policy drafts (we provide template, client reviews with their lawyer)

## 9. Forward-compat hooks (deliberate v1 decisions)

- `boutique_id` on every table → multi-tenant SaaS later without migration
- `vto_sessions.customer_id` nullable → anon customer-facing VTO already works; auth gating optional
- `design_generations.customer_id` nullable → flip on customer-facing design later behind tier gate
- `loyalty_tiers` configurable per boutique → no hardcoded Gold/Silver
- `automation_journeys.steps_json` data-driven → new journey types via UI, not code
- `settings` table for all per-boutique config → no env-var deploys for client tweaks

## 10. Success criteria for v1

- [ ] Owner can onboard a customer in <60s (name + phone, rest optional)
- [ ] Order confirmed → WhatsApp confirmation within 30s (via Inngest)
- [ ] VTO end-to-end (upload → result) in <45s p95
- [ ] Public site Lighthouse: Performance ≥ 90, SEO ≥ 95, Accessibility ≥ 90
- [ ] Admin pages: p95 page load < 2s on 4G
- [ ] Zero PCI scope (verified by Razorpay Checkout flow)
- [ ] GST invoice generated and emailed within 2min of order confirmation
- [ ] First 100 customers handled without staff manually composing a WhatsApp message
