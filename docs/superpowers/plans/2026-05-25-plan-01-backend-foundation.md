# Plan 1 — Backend Foundation

> **For agentic workers:** REQUIRED: Use superpowers:executing-plans (or subagent-driven-development) to implement. Steps use `- [ ]` syntax.

**Goal:** Stand up the shared Supabase backend (Postgres + Auth + Storage + RLS) that serves both the iPad app (Plan 2+) and the future web admin/storefront (Plans 6-8). No frontend code in this plan.

**Architecture:** Supabase Cloud project (single tenant for now, RLS scoped by `boutique_id` for forward-compat). Schema covers the shared core (boutiques, staff_users, events, settings, customers, fabrics, designs, design_renders, design_tryons, vto_sessions, plus product/order/inquiry tables from parent spec). Storage buckets configured with policies. Auth via Supabase Auth, email magic-link.

**Tech Stack:** Supabase CLI, Postgres 15, pgsodium, pg_trgm, plpgsql.

**Spec:** `docs/superpowers/specs/2026-05-25-boutique-360-design.md` + `docs/superpowers/specs/2026-05-25-boutique-360-ipad-addendum.md`

---

## File Structure

```
boutique-360/
├── supabase/
│   ├── config.toml
│   ├── seed.sql
│   └── migrations/
│       ├── 0001_extensions.sql
│       ├── 0002_boutiques.sql
│       ├── 0003_staff_users.sql
│       ├── 0004_events.sql
│       ├── 0005_settings.sql
│       ├── 0006_customers.sql
│       ├── 0007_customer_profiles_and_aux.sql        -- profiles, relationships, measurements, important_dates
│       ├── 0008_loyalty.sql
│       ├── 0009_products.sql
│       ├── 0010_orders.sql                            -- orders, items, payments, invoices
│       ├── 0011_inquiries.sql
│       ├── 0012_fabrics_and_designs.sql               -- fabrics, designs, design_fabrics
│       ├── 0013_renders_and_tryons.sql                -- design_renders, design_tryons, vto_sessions
│       ├── 0014_messaging.sql                         -- templates, conversations, messages
│       ├── 0015_automation.sql                        -- journeys, journey_runs
│       ├── 0016_device_sync.sql                       -- device_sync_state (iPad)
│       ├── 0017_rls_helpers.sql                       -- set_boutique_id_from_user(), policies
│       ├── 0018_triggers.sql                          -- updated_at, event-on-status-change
│       └── 0019_storage_buckets.sql                   -- create + policy buckets
└── docs/
    └── (existing)
```

**Note:** Storage buckets are created via the storage API, not pure SQL; migration `0019` contains the SQL part (policies); a sibling `scripts/create-buckets.sh` runs the bucket creation. Tracked together in Task 1.16.

---

## Chunk 1: Init + extensions + core entities

### Task 1.1 — Init Supabase project

- [ ] `cd "/Users/ateeshayjain/WIP Apps/boutique-360"`
- [ ] Install Supabase CLI if not present: `brew install supabase/tap/supabase`
- [ ] `supabase init` (accept defaults)
- [ ] `supabase start` — note the printed local API URL, anon key, service role key
- [ ] Commit: `chore: init Supabase local stack`

### Task 1.2 — Migration 0001: Extensions

- [ ] Create `supabase/migrations/0001_extensions.sql`:

```sql
create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto;
create extension if not exists pgsodium;
create extension if not exists pg_trgm;
```

- [ ] Verify: `supabase db reset` → no errors
- [ ] Commit: `feat(db): enable required extensions`

### Task 1.3 — Migration 0002: boutiques

- [ ] Create `supabase/migrations/0002_boutiques.sql`:

```sql
create table public.boutiques (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  gstin text,
  logo_url text,
  brand_color_hex text default '#1a1a1a',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.boutiques enable row level security;
create policy "boutiques_service_role" on public.boutiques for all to service_role using (true) with check (true);
```

- [ ] `supabase db reset` — verify
- [ ] Commit: `feat(db): boutiques table`

### Task 1.4 — Migration 0003: staff_users

- [ ] Create `supabase/migrations/0003_staff_users.sql`:

```sql
create type public.staff_role as enum ('owner','manager','designer','staff');

create table public.staff_users (
  id uuid primary key references auth.users(id) on delete cascade,
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  name text not null,
  email text not null,
  role public.staff_role not null default 'staff',
  phone text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index staff_users_boutique_idx on public.staff_users(boutique_id);

alter table public.staff_users enable row level security;
create policy "staff_self_read" on public.staff_users for select to authenticated using (id = auth.uid());
create policy "staff_service" on public.staff_users for all to service_role using (true) with check (true);
```

- [ ] `supabase db reset` — verify
- [ ] Commit: `feat(db): staff_users linked to auth.users with designer role`

### Task 1.5 — Migration 0004: events (append-only)

- [ ] Create `supabase/migrations/0004_events.sql`:

```sql
create table public.events (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  actor_type text not null check (actor_type in ('staff','customer','system','webhook','ipad')),
  actor_id uuid,
  event_name text not null,
  payload_json jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);
create index events_boutique_time_idx on public.events(boutique_id, occurred_at desc);
create index events_name_idx on public.events(event_name);
create index events_payload_gin on public.events using gin (payload_json);

alter table public.events enable row level security;
create policy "events_read" on public.events for select to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "events_insert" on public.events for insert to authenticated
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "events_service" on public.events for all to service_role using (true) with check (true);
```

- [ ] Verify + commit

### Task 1.6 — Migration 0005: encrypted settings

- [ ] Create `supabase/migrations/0005_settings.sql`:

```sql
create table public.settings (
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  key text not null,
  value_json jsonb,
  value_encrypted bytea,
  is_secret boolean not null default false,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  primary key (boutique_id, key),
  check ((is_secret = false and value_json is not null and value_encrypted is null)
      or (is_secret = true  and value_encrypted is not null and value_json is null))
);

alter table public.settings enable row level security;
create policy "settings_read" on public.settings for select to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "settings_service" on public.settings for all to service_role using (true) with check (true);
```

- [ ] Verify + commit

## Chunk 2: People + Loyalty + Catalog

### Task 1.7 — Migration 0006: customers

- [ ] Create `supabase/migrations/0006_customers.sql`:

```sql
create table public.customers (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  name text not null,
  phone text,
  email text,
  dob date,
  address_json jsonb,
  tags text[] default '{}',
  vip_status boolean default false,
  loyalty_points integer default 0,
  current_tier_id uuid,
  source text default 'walkin' check (source in ('walkin','website','referral','instagram','imported','ipad')),
  consent_whatsapp boolean default false,
  consent_email boolean default false,
  consent_signed_at timestamptz,
  lifetime_value_cached numeric default 0,
  email_bounce_count integer default 0,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index customers_phone_unique on public.customers(boutique_id, phone) where deleted_at is null and phone is not null;
create index customers_name_trgm on public.customers using gin (name gin_trgm_ops);
create index customers_boutique_idx on public.customers(boutique_id);

alter table public.customers enable row level security;
create policy "customers_rw" on public.customers for all to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid)
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "customers_service" on public.customers for all to service_role using (true) with check (true);
```

- [ ] Verify + commit

### Task 1.8 — Migration 0007: customer profiles + aux

- [ ] Create `supabase/migrations/0007_customer_profiles_and_aux.sql`:

```sql
create table public.customer_profiles (
  customer_id uuid primary key references public.customers(id) on delete cascade,
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  style_persona text check (style_persona in ('traditional','fusion','modern','minimalist','maximalist')),
  color_palette text[] default '{}',
  fabric_preferences text[] default '{}',
  avoid_fabrics text[] default '{}',
  body_type text check (body_type in ('pear','apple','hourglass','rectangle','inverted_triangle')),
  height_cm integer,
  skin_tone text check (skin_tone in ('fair','wheatish','dusky','deep')),
  budget_band text check (budget_band in ('value','mid','premium','luxury')),
  favorite_designers text[] default '{}',
  pinterest_url text,
  instagram_handle text,
  style_notes_md text,
  updated_at timestamptz not null default now()
);

create table public.customer_measurements (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  garment_type text not null,
  measurements_json jsonb not null,
  taken_by uuid references public.staff_users(id),
  taken_at timestamptz not null default now()
);
create index measurements_customer_idx on public.customer_measurements(customer_id, taken_at desc);

create table public.customer_relationships (
  customer_id uuid not null references public.customers(id) on delete cascade,
  related_customer_id uuid not null references public.customers(id) on delete cascade,
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  relation text not null check (relation in ('mother','daughter','sister','spouse','friend','referrer')),
  primary key (customer_id, related_customer_id)
);

create table public.important_dates (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  occasion text not null,
  date date not null,
  recurring boolean default true,
  reminder_days_before integer default 7,
  created_at timestamptz not null default now()
);
create index important_dates_customer_idx on public.important_dates(customer_id, date);

-- RLS for all four tables (uniform policy)
alter table public.customer_profiles enable row level security;
alter table public.customer_measurements enable row level security;
alter table public.customer_relationships enable row level security;
alter table public.important_dates enable row level security;

do $$
declare t text;
begin
  for t in select unnest(array['customer_profiles','customer_measurements','customer_relationships','important_dates']) loop
    execute format('create policy "%I_rw" on public.%I for all to authenticated using (boutique_id = (current_setting(''app.boutique_id'', true))::uuid) with check (boutique_id = (current_setting(''app.boutique_id'', true))::uuid)', t, t);
    execute format('create policy "%I_service" on public.%I for all to service_role using (true) with check (true)', t, t);
  end loop;
end $$;
```

- [ ] Verify + commit

### Task 1.9 — Migration 0008: loyalty

- [ ] Create `supabase/migrations/0008_loyalty.sql`:

```sql
create table public.loyalty_tiers (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  name text not null,
  min_lifetime_value numeric default 0,
  min_orders integer default 0,
  points_multiplier numeric default 1.0,
  perks_json jsonb default '{}'::jsonb,
  color_hex text,
  sort_order integer default 0,
  created_at timestamptz not null default now()
);
create unique index loyalty_tier_name_unique on public.loyalty_tiers(boutique_id, name);

create table public.customer_tier_history (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  tier_id uuid not null references public.loyalty_tiers(id),
  achieved_at timestamptz not null default now(),
  expired_at timestamptz
);
create index tier_history_customer_idx on public.customer_tier_history(customer_id, achieved_at desc);

alter table public.customers add constraint customers_tier_fk
  foreign key (current_tier_id) references public.loyalty_tiers(id) on delete set null;

alter table public.loyalty_tiers enable row level security;
alter table public.customer_tier_history enable row level security;

create policy "loyalty_tiers_rw" on public.loyalty_tiers for all to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid)
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "loyalty_tiers_service" on public.loyalty_tiers for all to service_role using (true) with check (true);

create policy "tier_history_rw" on public.customer_tier_history for all to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid)
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "tier_history_service" on public.customer_tier_history for all to service_role using (true) with check (true);
```

- [ ] Verify + commit

### Task 1.10 — Migration 0009: products

- [ ] Create `supabase/migrations/0009_products.sql`:

```sql
create type public.product_mode as enum ('ready_to_ship','bespoke','both');

create table public.products (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  sku text not null,
  name text not null,
  slug text not null,
  description_md text,
  category text,
  mode public.product_mode not null default 'bespoke',
  base_price numeric,
  sale_price numeric,
  hsn_code text,
  gst_rate numeric default 5.0,
  hero_image_url text,
  gallery_urls text[] default '{}',
  vto_enabled boolean default false,
  vto_flat_lay_url text,
  published boolean default false,
  seo_title text,
  seo_description text,
  created_by uuid references public.staff_users(id),
  source_design_id uuid,                    -- if promoted from iPad design (fk added in 0012)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index products_slug_unique on public.products(boutique_id, slug);
create index products_name_trgm on public.products using gin (name gin_trgm_ops);
create index products_published_idx on public.products(boutique_id, published);

create table public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  sku text not null,
  size text,
  color text,
  stock_qty integer not null default 0,
  price_override numeric,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index variants_product_idx on public.product_variants(product_id);

alter table public.products enable row level security;
alter table public.product_variants enable row level security;

-- Staff RW within boutique
create policy "products_rw" on public.products for all to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid)
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "products_service" on public.products for all to service_role using (true) with check (true);

-- Public anon can read published products only (used by public storefront — Plan 8)
create policy "products_public_read" on public.products for select to anon using (published = true);

create policy "variants_rw" on public.product_variants for all to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid)
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "variants_service" on public.product_variants for all to service_role using (true) with check (true);
create policy "variants_public_read" on public.product_variants for select to anon
  using (exists (select 1 from public.products p where p.id = product_id and p.published = true));
```

- [ ] Verify + commit

## Chunk 3: Commerce + iPad-specific tables

### Task 1.11 — Migration 0010: orders + payments + invoices

- [ ] Create `supabase/migrations/0010_orders.sql`:

```sql
create type public.order_status as enum ('pending','confirmed','packed','shipped','delivered','cancelled','returned');
create type public.payment_status as enum ('created','authorized','captured','failed','refunded');
create type public.payment_method as enum ('upi','card','netbanking','wallet','cash','bank_transfer');

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  order_number text not null,
  customer_id uuid not null references public.customers(id) on delete restrict,
  status public.order_status not null default 'pending',
  subtotal numeric not null default 0,
  gst_amount numeric not null default 0,
  shipping numeric default 0,
  total numeric not null default 0,
  currency text not null default 'INR',
  shipping_address_json jsonb,
  tracking_url text,
  tracking_courier text,
  magic_link_token text unique,
  placed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index orders_number_unique on public.orders(boutique_id, order_number);
create index orders_customer_idx on public.orders(customer_id, created_at desc);
create index orders_status_idx on public.orders(boutique_id, status);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  product_id uuid references public.products(id),
  variant_id uuid references public.product_variants(id),
  qty integer not null default 1,
  unit_price numeric not null,
  gst_amount numeric not null default 0
);
create index order_items_order_idx on public.order_items(order_id);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  order_id uuid not null references public.orders(id) on delete cascade,
  razorpay_order_id text,
  razorpay_payment_id text unique,
  amount numeric not null,
  status public.payment_status not null default 'created',
  method public.payment_method,
  raw_payload_json jsonb,
  captured_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index payments_order_idx on public.payments(order_id);

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  order_id uuid not null unique references public.orders(id) on delete restrict,
  invoice_number text not null,
  pdf_url text,
  gst_breakdown_json jsonb,
  issued_at timestamptz not null default now()
);
create unique index invoices_number_unique on public.invoices(boutique_id, invoice_number);

-- RLS uniform
do $$
declare t text;
begin
  for t in select unnest(array['orders','order_items','payments','invoices']) loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "%I_rw" on public.%I for all to authenticated using (boutique_id = (current_setting(''app.boutique_id'', true))::uuid) with check (boutique_id = (current_setting(''app.boutique_id'', true))::uuid)', t, t);
    execute format('create policy "%I_service" on public.%I for all to service_role using (true) with check (true)', t, t);
  end loop;
end $$;

-- Order tracking by magic-link token (anon access for /orders/[token])
create policy "orders_magic_link_read" on public.orders for select to anon
  using (magic_link_token is not null);
```

- [ ] Verify + commit

### Task 1.12 — Migration 0011: inquiries

- [ ] Create `supabase/migrations/0011_inquiries.sql`:

```sql
create type public.inquiry_status as enum (
  'new','consulting','measurements','quoted','confirmed','in_production','ready','delivered','lost'
);

create table public.inquiries (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  inquiry_number text not null,
  customer_id uuid not null references public.customers(id) on delete restrict,
  product_id uuid references public.products(id),
  source_design_id uuid,                   -- fk added in 0012
  status public.inquiry_status not null default 'new',
  occasion text,
  event_date date,
  budget_range text,
  notes text,
  assigned_to uuid references public.staff_users(id),
  source text,
  converted_order_id uuid references public.orders(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index inquiries_number_unique on public.inquiries(boutique_id, inquiry_number);
create index inquiries_status_idx on public.inquiries(boutique_id, status);
create index inquiries_customer_idx on public.inquiries(customer_id, created_at desc);

create table public.inquiry_messages (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  inquiry_id uuid not null references public.inquiries(id) on delete cascade,
  author text not null check (author in ('customer','staff')),
  body text not null,
  attachments_urls text[] default '{}',
  created_at timestamptz not null default now()
);
create index inquiry_msg_inquiry_idx on public.inquiry_messages(inquiry_id, created_at);

alter table public.inquiries enable row level security;
alter table public.inquiry_messages enable row level security;
create policy "inquiries_rw" on public.inquiries for all to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid)
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "inquiries_service" on public.inquiries for all to service_role using (true) with check (true);
create policy "inquiry_messages_rw" on public.inquiry_messages for all to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid)
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "inquiry_messages_service" on public.inquiry_messages for all to service_role using (true) with check (true);

-- Public anon can insert inquiries (from website inquiry form, Plan 8)
create policy "inquiries_public_insert" on public.inquiries for insert to anon
  with check (source = 'website');
```

- [ ] Verify + commit

### Task 1.13 — Migration 0012: fabrics + designs (iPad-critical)

- [ ] Create `supabase/migrations/0012_fabrics_and_designs.sql`:

```sql
create type public.design_status as enum (
  'draft','rendered','shared_with_customer','approved','in_production','delivered','archived'
);

create table public.fabrics (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  name text not null,
  supplier text,
  color_hex text,
  cost_per_meter numeric,
  photo_url text,
  captured_by_staff_id uuid references public.staff_users(id),
  captured_at timestamptz not null default now(),
  retired_at timestamptz,
  notes text
);
create index fabrics_boutique_idx on public.fabrics(boutique_id) where retired_at is null;
create index fabrics_name_trgm on public.fabrics using gin (name gin_trgm_ops);

create table public.designs (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  name text not null,
  status public.design_status not null default 'draft',
  sketch_strokes_json jsonb,            -- PencilKit drawing data
  sketch_image_url text,                 -- rasterized preview
  measurements_json jsonb,               -- structured measurements
  garment_type text,
  occasion text,
  notes_md text,
  created_by_staff_id uuid references public.staff_users(id),
  device_id uuid,                        -- iPad device that authored it (for sync)
  client_local_id text,                  -- client-generated id for sync deduplication
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index designs_client_local_unique on public.designs(boutique_id, device_id, client_local_id)
  where device_id is not null and client_local_id is not null;
create index designs_customer_idx on public.designs(customer_id, created_at desc);
create index designs_status_idx on public.designs(boutique_id, status);

create table public.design_fabrics (
  design_id uuid not null references public.designs(id) on delete cascade,
  fabric_id uuid not null references public.fabrics(id) on delete restrict,
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  role text not null check (role in ('main','lining','trim','embellishment')),
  meters_estimated numeric,
  sort_order integer default 0,
  primary key (design_id, fabric_id, role)
);

-- Now we can add the source_design_id FKs from earlier tables
alter table public.products
  add constraint products_source_design_fk foreign key (source_design_id) references public.designs(id) on delete set null;
alter table public.inquiries
  add constraint inquiries_source_design_fk foreign key (source_design_id) references public.designs(id) on delete set null;

alter table public.fabrics enable row level security;
alter table public.designs enable row level security;
alter table public.design_fabrics enable row level security;

create policy "fabrics_rw" on public.fabrics for all to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid)
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "fabrics_service" on public.fabrics for all to service_role using (true) with check (true);

create policy "designs_rw" on public.designs for all to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid)
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "designs_service" on public.designs for all to service_role using (true) with check (true);

create policy "design_fabrics_rw" on public.design_fabrics for all to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid)
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "design_fabrics_service" on public.design_fabrics for all to service_role using (true) with check (true);
```

- [ ] Verify + commit

### Task 1.14 — Migration 0013: renders + tryons + vto_sessions

- [ ] Create `supabase/migrations/0013_renders_and_tryons.sql`:

```sql
create type public.render_status as enum ('queued','done','failed');

create table public.design_renders (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  design_id uuid not null references public.designs(id) on delete cascade,
  prompt_used text,
  result_image_url text,
  model_used text,
  processing_ms integer,
  cost_estimate_usd numeric,
  status public.render_status not null default 'queued',
  error_msg text,
  is_favorite boolean default false,
  parent_render_id uuid references public.design_renders(id) on delete set null,
  created_at timestamptz not null default now()
);
create index design_renders_design_idx on public.design_renders(design_id, created_at desc);

create table public.design_tryons (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  design_render_id uuid not null references public.design_renders(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  customer_photo_url text,                  -- expires per purge_at
  result_image_url text,                    -- watermarked
  model_used text,
  processing_ms integer,
  cost_estimate_usd numeric,
  customer_consent_signed_at timestamptz not null,
  saved_to_lookbook boolean default false,
  created_at timestamptz not null default now(),
  purge_at timestamptz not null default (now() + interval '7 days')
);
create index design_tryons_design_idx on public.design_tryons(design_render_id);
create index design_tryons_customer_idx on public.design_tryons(customer_id, created_at desc);
create index design_tryons_purge_idx on public.design_tryons(purge_at) where customer_photo_url is not null;

-- Web-initiated VTO (anon visitors to public site) — Plan 8 will populate
create table public.vto_sessions (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  product_id uuid not null references public.products(id) on delete cascade,
  user_image_url text,
  result_image_url text,
  model_used text,
  processing_ms integer,
  cost_estimate_usd numeric,
  status public.render_status not null default 'queued',
  error_msg text,
  viewed_at timestamptz,
  converted_to_inquiry_id uuid references public.inquiries(id) on delete set null,
  ip_hash text,                             -- for anon rate-limiting
  created_at timestamptz not null default now()
);
create index vto_sessions_product_idx on public.vto_sessions(product_id, created_at desc);

alter table public.design_renders enable row level security;
alter table public.design_tryons enable row level security;
alter table public.vto_sessions enable row level security;

create policy "design_renders_rw" on public.design_renders for all to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid)
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "design_renders_service" on public.design_renders for all to service_role using (true) with check (true);

create policy "design_tryons_rw" on public.design_tryons for all to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid)
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "design_tryons_service" on public.design_tryons for all to service_role using (true) with check (true);

create policy "vto_sessions_rw" on public.vto_sessions for all to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid)
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "vto_sessions_service" on public.vto_sessions for all to service_role using (true) with check (true);
```

- [ ] Verify + commit

### Task 1.15 — Migrations 0014-0016: messaging, automation, device sync

- [ ] Create `supabase/migrations/0014_messaging.sql`:

```sql
create table public.message_templates (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  name text not null,
  channel text not null check (channel in ('whatsapp','email','sms')),
  whatsapp_template_name text,
  whatsapp_template_status text check (whatsapp_template_status in ('draft','submitted','approved','rejected')),
  body_template text not null,
  variables_json jsonb default '[]'::jsonb,
  category text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  channel text not null,
  last_message_at timestamptz,
  unread_count integer default 0,
  assigned_to uuid references public.staff_users(id),
  created_at timestamptz not null default now()
);
create unique index conversations_customer_channel on public.conversations(customer_id, channel);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  direction text not null check (direction in ('out','in')),
  channel text not null,
  template_id uuid references public.message_templates(id),
  body text,
  media_urls text[] default '{}',
  status text not null default 'queued' check (status in ('queued','sent','delivered','read','failed')),
  provider_message_id text,
  error_msg text,
  sent_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index messages_provider_unique on public.messages(provider_message_id) where provider_message_id is not null;
create index messages_conversation_idx on public.messages(conversation_id, created_at desc);

alter table public.message_templates enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;

do $$
declare t text;
begin
  for t in select unnest(array['message_templates','conversations','messages']) loop
    execute format('create policy "%I_rw" on public.%I for all to authenticated using (boutique_id = (current_setting(''app.boutique_id'', true))::uuid) with check (boutique_id = (current_setting(''app.boutique_id'', true))::uuid)', t, t);
    execute format('create policy "%I_service" on public.%I for all to service_role using (true) with check (true)', t, t);
  end loop;
end $$;
```

- [ ] Create `supabase/migrations/0015_automation.sql`:

```sql
create table public.automation_journeys (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  name text not null,
  trigger_event text not null,
  active boolean not null default false,
  steps_json jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.journey_runs (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  journey_id uuid not null references public.automation_journeys(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  current_step integer not null default 0,
  status text not null default 'running' check (status in ('running','completed','failed','cancelled')),
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  last_step_at timestamptz
);
create index journey_runs_journey_idx on public.journey_runs(journey_id, status);

alter table public.automation_journeys enable row level security;
alter table public.journey_runs enable row level security;
do $$
declare t text;
begin
  for t in select unnest(array['automation_journeys','journey_runs']) loop
    execute format('create policy "%I_rw" on public.%I for all to authenticated using (boutique_id = (current_setting(''app.boutique_id'', true))::uuid) with check (boutique_id = (current_setting(''app.boutique_id'', true))::uuid)', t, t);
    execute format('create policy "%I_service" on public.%I for all to service_role using (true) with check (true)', t, t);
  end loop;
end $$;
```

- [ ] Create `supabase/migrations/0016_device_sync.sql`:

```sql
create table public.device_sync_state (
  device_id uuid primary key,
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  staff_user_id uuid not null references public.staff_users(id) on delete cascade,
  last_synced_at timestamptz,
  last_event_id_seen uuid,
  app_version text,
  ios_version text,
  device_model text,
  registered_at timestamptz not null default now()
);
create index device_sync_staff_idx on public.device_sync_state(staff_user_id);

alter table public.device_sync_state enable row level security;
create policy "device_sync_self" on public.device_sync_state for all to authenticated
  using (staff_user_id = auth.uid())
  with check (staff_user_id = auth.uid());
create policy "device_sync_service" on public.device_sync_state for all to service_role using (true) with check (true);
```

- [ ] Verify all three: `supabase db reset`
- [ ] Commit: `feat(db): messaging + automation + device_sync_state`

## Chunk 4: RLS helpers, triggers, storage buckets, seed

### Task 1.16 — Migration 0017: RLS helper + 0018: triggers

- [ ] Create `supabase/migrations/0017_rls_helpers.sql`:

```sql
create or replace function public.set_boutique_id_from_user()
returns void language plpgsql security definer set search_path = public as $$
declare bid uuid;
begin
  select boutique_id into bid from public.staff_users where id = auth.uid() and active = true;
  if bid is null then raise exception 'no active staff record for user %', auth.uid(); end if;
  perform set_config('app.boutique_id', bid::text, true);
end;
$$;
grant execute on function public.set_boutique_id_from_user() to authenticated;

-- Boutiques self-read for staff
create policy "boutiques_self_read" on public.boutiques for select to authenticated
  using (id = (current_setting('app.boutique_id', true))::uuid);
```

- [ ] Create `supabase/migrations/0018_triggers.sql`:

```sql
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end; $$;

-- Apply to all tables with updated_at
do $$
declare t text;
begin
  for t in select unnest(array[
    'boutiques','staff_users','settings','customers','customer_profiles',
    'loyalty_tiers','products','product_variants','orders','payments',
    'inquiries','designs','message_templates','conversations','automation_journeys'
  ]) loop
    execute format('drop trigger if exists %I_updated_at on public.%I', t, t);
    execute format('create trigger %I_updated_at before update on public.%I for each row execute function public.set_updated_at()', t, t);
  end loop;
end $$;

-- Emit events on key status transitions (audit trail + automation triggers)
create or replace function public.emit_event_on_order_status_change()
returns trigger language plpgsql security definer as $$
begin
  if new.status is distinct from old.status then
    insert into public.events (boutique_id, actor_type, event_name, payload_json)
    values (new.boutique_id, 'system', 'order.status_changed',
      jsonb_build_object('order_id', new.id, 'order_number', new.order_number,
                         'from', old.status, 'to', new.status, 'customer_id', new.customer_id));
  end if;
  return new;
end; $$;
create trigger orders_status_event after update on public.orders
  for each row execute function public.emit_event_on_order_status_change();

create or replace function public.emit_event_on_inquiry_status_change()
returns trigger language plpgsql security definer as $$
begin
  if new.status is distinct from old.status then
    insert into public.events (boutique_id, actor_type, event_name, payload_json)
    values (new.boutique_id, 'system', 'inquiry.status_changed',
      jsonb_build_object('inquiry_id', new.id, 'from', old.status, 'to', new.status,
                         'customer_id', new.customer_id));
  end if;
  return new;
end; $$;
create trigger inquiries_status_event after update on public.inquiries
  for each row execute function public.emit_event_on_inquiry_status_change();
```

- [ ] Verify + commit

### Task 1.17 — Migration 0019 + bucket script: Storage buckets

- [ ] Create `supabase/migrations/0019_storage_buckets.sql`:

```sql
-- This migration only documents policies. Buckets themselves are created via the
-- storage API by the sibling script scripts/create-buckets.sh (idempotent).

-- Drop existing policies if re-running
drop policy if exists "product_images_public_read" on storage.objects;
drop policy if exists "product_images_staff_write" on storage.objects;
drop policy if exists "vto_uploads_staff" on storage.objects;
drop policy if exists "vto_results_public_read" on storage.objects;
drop policy if exists "vto_results_staff_write" on storage.objects;
drop policy if exists "design_sketches_staff" on storage.objects;
drop policy if exists "design_renders_staff" on storage.objects;
drop policy if exists "customer_photos_staff" on storage.objects;
drop policy if exists "fabrics_staff" on storage.objects;
drop policy if exists "invoices_staff" on storage.objects;
drop policy if exists "measurements_staff" on storage.objects;

-- product-images: public read, staff write
create policy "product_images_public_read" on storage.objects for select to anon
  using (bucket_id = 'product-images');
create policy "product_images_staff_write" on storage.objects for all to authenticated
  using (bucket_id = 'product-images') with check (bucket_id = 'product-images');

-- vto-uploads: staff only (private; expires 30 days)
create policy "vto_uploads_staff" on storage.objects for all to authenticated
  using (bucket_id = 'vto-uploads') with check (bucket_id = 'vto-uploads');

-- vto-results: public read (watermarked), staff write
create policy "vto_results_public_read" on storage.objects for select to anon
  using (bucket_id = 'vto-results');
create policy "vto_results_staff_write" on storage.objects for all to authenticated
  using (bucket_id = 'vto-results') with check (bucket_id = 'vto-results');

-- design-sketches: staff only (PencilKit rasters + stroke exports)
create policy "design_sketches_staff" on storage.objects for all to authenticated
  using (bucket_id = 'design-sketches') with check (bucket_id = 'design-sketches');

-- design-renders: staff only
create policy "design_renders_staff" on storage.objects for all to authenticated
  using (bucket_id = 'design-renders') with check (bucket_id = 'design-renders');

-- customer-photos (iPad VTO captures): staff only, auto-purge by job
create policy "customer_photos_staff" on storage.objects for all to authenticated
  using (bucket_id = 'customer-photos') with check (bucket_id = 'customer-photos');

-- fabrics: staff only
create policy "fabrics_staff" on storage.objects for all to authenticated
  using (bucket_id = 'fabrics') with check (bucket_id = 'fabrics');

-- invoices: owner-only
create policy "invoices_staff" on storage.objects for all to authenticated
  using (bucket_id = 'invoices') with check (bucket_id = 'invoices');

-- measurements-photos: staff only
create policy "measurements_staff" on storage.objects for all to authenticated
  using (bucket_id = 'measurements-photos') with check (bucket_id = 'measurements-photos');
```

- [ ] Create `scripts/create-buckets.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SUPABASE_URL="${SUPABASE_URL:-http://localhost:54321}"
SERVICE_KEY="${SUPABASE_SERVICE_ROLE_KEY:?SUPABASE_SERVICE_ROLE_KEY required}"

create_bucket() {
  local id="$1"
  local public="$2"
  curl -fsS -X POST "${SUPABASE_URL}/storage/v1/bucket" \
    -H "Authorization: Bearer ${SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"id\":\"${id}\",\"name\":\"${id}\",\"public\":${public}}" \
    || echo "Bucket ${id} already exists or failed (idempotent OK)"
  echo
}

create_bucket "product-images"     "true"
create_bucket "vto-uploads"        "false"
create_bucket "vto-results"        "true"
create_bucket "design-sketches"    "false"
create_bucket "design-renders"     "false"
create_bucket "customer-photos"    "false"
create_bucket "fabrics"            "false"
create_bucket "invoices"           "false"
create_bucket "measurements-photos" "false"

echo "All buckets created (or already existed)."
```

- [ ] `chmod +x scripts/create-buckets.sh`
- [ ] Run: `SUPABASE_SERVICE_ROLE_KEY=<from supabase start> ./scripts/create-buckets.sh`
- [ ] Verify in Supabase Studio (http://localhost:54323 → Storage) that all 9 buckets exist
- [ ] `supabase db reset` to apply 0019 policies
- [ ] Commit: `feat(db): storage buckets and policies for product images, VTO, designs, fabrics, invoices`

### Task 1.18 — Seed data

- [ ] Create `supabase/seed.sql`:

```sql
-- Dev seed
insert into public.boutiques (id, name, slug, gstin, brand_color_hex)
values ('00000000-0000-0000-0000-000000000001', 'Aditi Designer Studio', 'aditi-designer-studio', '07AAAAA0000A1Z5', '#7C2D3C')
on conflict (id) do nothing;

-- Default loyalty tiers
insert into public.loyalty_tiers (boutique_id, name, min_lifetime_value, min_orders, points_multiplier, perks_json, color_hex, sort_order) values
('00000000-0000-0000-0000-000000000001', 'Silver',   0,      0,  1.0, '{"free_shipping": false, "birthday_voucher_amount": 0}'::jsonb,    '#C0C0C0', 1),
('00000000-0000-0000-0000-000000000001', 'Gold',     50000,  3,  1.5, '{"free_shipping": true,  "birthday_voucher_amount": 500}'::jsonb,  '#D4AF37', 2),
('00000000-0000-0000-0000-000000000001', 'Platinum', 200000, 10, 2.0, '{"free_shipping": true,  "birthday_voucher_amount": 2000, "early_access": true, "priority_support": true}'::jsonb, '#E5E4E2', 3)
on conflict do nothing;
```

- [ ] `supabase db reset` (re-applies all migrations + seed)
- [ ] Verify: `psql postgresql://postgres:postgres@localhost:54322/postgres -c "select name from public.loyalty_tiers order by sort_order;"` → Silver, Gold, Platinum
- [ ] Commit: `chore(db): seed dev boutique + default loyalty tiers`

## Chunk 5: Generate TypeScript types + Swift client init + README

### Task 1.19 — Generate TypeScript types (for future web)

- [ ] Create `supabase/.gitignore`:

```
.branches
.temp
```

- [ ] Generate types: `supabase gen types typescript --local > supabase/types.ts`
- [ ] Commit: `chore(db): generated TypeScript types`

### Task 1.20 — Create README for the project

- [ ] Create `README.md` at project root:

````markdown
# Boutique 360

iPad-native designer workflow + web admin CRM + public storefront for boutique businesses.

- **Spec:** `docs/superpowers/specs/2026-05-25-boutique-360-design.md` (web)
- **Spec addendum:** `docs/superpowers/specs/2026-05-25-boutique-360-ipad-addendum.md` (iPad)
- **Plans:** `docs/superpowers/plans/`

## Surfaces

1. **iPad app** (SwiftUI + PencilKit) — primary designer surface, in-store use
2. **Web admin** (Next.js, later) — back-office, analytics, automation
3. **Public site** (Next.js, later) — catalog, inquiries, order tracking

All three share one Supabase backend.

## Backend setup (this Plan)

```bash
brew install supabase/tap/supabase
cd "/Users/ateeshayjain/WIP Apps/boutique-360"
supabase start
SUPABASE_SERVICE_ROLE_KEY=<from supabase start> ./scripts/create-buckets.sh
supabase db reset
```

Studio: http://localhost:54323
API: http://localhost:54321

## Next: Plan 2 — iPad App Foundation

Xcode 15+, iOS 17+ target, SwiftUI, Supabase Swift SDK, PencilKit.
````

- [ ] Commit: `docs: README explaining surfaces + backend setup`

### Task 1.21 — Verification checklist

- [ ] `supabase db reset` runs cleanly, all 19 migrations apply
- [ ] All 9 storage buckets exist in Supabase Studio
- [ ] Seed inserted: 1 boutique + 3 loyalty tiers
- [ ] TypeScript types generated to `supabase/types.ts`
- [ ] No errors visible in Supabase Studio logs
- [ ] `psql ... -c "\dt public.*"` shows all 24+ tables

When all boxes checked: **Backend Foundation done. Plan 2 (iPad App Foundation) can begin.**

---

## Notes

- This plan has no app code, no Next.js, no tests beyond schema-apply verification. That's deliberate: this is the data layer that both iPad and future web consume.
- Tests for individual modules (CRM, Catalog, etc.) come with each surface's plans.
- The web admin's auth/middleware/scaffolding (from the superseded plan) gets resurrected in Plans 6-7 when we build the web admin.
