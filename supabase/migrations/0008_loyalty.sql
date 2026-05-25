-- Plan 1, Task 1.9 — loyalty tiers + customer_tier_history
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
