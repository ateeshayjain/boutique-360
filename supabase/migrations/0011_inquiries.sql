-- Plan 1, Task 1.12 — inquiries + inquiry_messages
create type public.inquiry_status as enum (
  'new','consulting','measurements','quoted','confirmed','in_production','ready','delivered','lost'
);

create table public.inquiries (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  inquiry_number text not null,
  customer_id uuid not null references public.customers(id) on delete restrict,
  product_id uuid references public.products(id),
  source_design_id uuid,
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

create policy "inquiries_public_insert" on public.inquiries for insert to anon
  with check (source = 'website');
