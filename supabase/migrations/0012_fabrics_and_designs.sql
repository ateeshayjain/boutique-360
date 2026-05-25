-- Plan 1, Task 1.13 — fabrics + designs + design_fabrics (iPad-critical workflow tables)
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
  sketch_strokes_json jsonb,
  sketch_image_url text,
  measurements_json jsonb,
  garment_type text,
  occasion text,
  notes_md text,
  created_by_staff_id uuid references public.staff_users(id),
  device_id uuid,
  client_local_id text,
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
