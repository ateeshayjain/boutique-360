-- Plan 1, Task 1.14 — design_renders, design_tryons (iPad VTO), vto_sessions (web VTO)
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
  customer_photo_url text,
  result_image_url text,
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
  ip_hash text,
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
