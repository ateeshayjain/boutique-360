-- Plan 1, Task 1.4 — staff_users (1:1 with auth.users)
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
