-- Plan 1, Task 1.7 — customers (DPDP soft-delete, partial unique on phone)
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
create unique index customers_phone_unique on public.customers(boutique_id, phone)
  where deleted_at is null and phone is not null;
create index customers_name_trgm on public.customers using gin (name gin_trgm_ops);
create index customers_boutique_idx on public.customers(boutique_id);

alter table public.customers enable row level security;
create policy "customers_rw" on public.customers for all to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid)
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "customers_service" on public.customers for all to service_role using (true) with check (true);
