-- Plan 1, Task 1.8 — customer_profiles, measurements, relationships, important_dates
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
