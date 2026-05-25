-- Plan 1, Task 1.3 — boutiques (top-level tenant entity)
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
