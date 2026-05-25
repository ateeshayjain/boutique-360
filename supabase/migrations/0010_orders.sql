-- Plan 1, Task 1.11 — orders, items, payments, invoices
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

do $$
declare t text;
begin
  for t in select unnest(array['orders','order_items','payments','invoices']) loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "%I_rw" on public.%I for all to authenticated using (boutique_id = (current_setting(''app.boutique_id'', true))::uuid) with check (boutique_id = (current_setting(''app.boutique_id'', true))::uuid)', t, t);
    execute format('create policy "%I_service" on public.%I for all to service_role using (true) with check (true)', t, t);
  end loop;
end $$;

create policy "orders_magic_link_read" on public.orders for select to anon
  using (magic_link_token is not null);
