-- Plan 1, Task 1.10 — products + variants
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
  source_design_id uuid,
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

create policy "products_rw" on public.products for all to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid)
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "products_service" on public.products for all to service_role using (true) with check (true);
create policy "products_public_read" on public.products for select to anon using (published = true);

create policy "variants_rw" on public.product_variants for all to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid)
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "variants_service" on public.product_variants for all to service_role using (true) with check (true);
create policy "variants_public_read" on public.product_variants for select to anon
  using (exists (select 1 from public.products p where p.id = product_id and p.published = true));
