-- BACKFILLED 2026-07-31 from supabase_migrations.schema_migrations.
-- Applied to production 2026-05-26 (version 20260526064940).
-- RECORD of SQL that has already run — do not re-apply as a new migration.
--
-- Adds appointments + alterations (the fitting/alteration loop) and
-- orders.fulfillment_method. Both new tables use the correct post-0020 RLS
-- shape: current_boutique_id() with `with check` on both the authenticated
-- and service_role policies.

-- fulfillment method on orders
do $$ begin
  if not exists (select 1 from information_schema.columns where table_name='orders' and column_name='fulfillment_method') then
    alter table public.orders add column fulfillment_method text not null default 'pickup'
      check (fulfillment_method in ('pickup','ship'));
  end if;
end $$;

-- enums (Postgres has no IF NOT EXISTS for CREATE TYPE)
do $$ begin
  create type public.appointment_type as enum ('fitting','consultation','delivery','pickup','other');
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.appointment_status as enum ('scheduled','completed','cancelled','no_show');
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.alteration_status as enum ('requested','in_progress','completed','cancelled');
exception when duplicate_object then null;
end $$;

create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  order_id uuid references public.orders(id) on delete set null,
  type public.appointment_type not null default 'fitting',
  scheduled_at timestamptz not null,
  duration_minutes integer not null default 30,
  status public.appointment_status not null default 'scheduled',
  notes text,
  reminder_sent boolean default false,
  created_by uuid references public.staff_users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists appointments_boutique_time_idx on public.appointments(boutique_id, scheduled_at);
create index if not exists appointments_customer_idx on public.appointments(customer_id, scheduled_at desc);
create index if not exists appointments_order_idx on public.appointments(order_id) where order_id is not null;

alter table public.appointments enable row level security;
drop policy if exists "appointments_rw" on public.appointments;
create policy "appointments_rw" on public.appointments for all to authenticated
  using (boutique_id = public.current_boutique_id())
  with check (boutique_id = public.current_boutique_id());
drop policy if exists "appointments_service" on public.appointments;
create policy "appointments_service" on public.appointments for all to service_role using (true) with check (true);

drop trigger if exists appointments_updated_at on public.appointments;
create trigger appointments_updated_at before update on public.appointments
  for each row execute function public.set_updated_at();

create table if not exists public.alterations (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  order_id uuid not null references public.orders(id) on delete cascade,
  appointment_id uuid references public.appointments(id) on delete set null,
  round_number integer not null default 1,
  status public.alteration_status not null default 'requested',
  request_notes text not null,
  internal_notes text,
  target_date date,
  completed_at timestamptz,
  created_by uuid references public.staff_users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists alterations_order_idx on public.alterations(order_id, round_number);
create index if not exists alterations_boutique_status_idx on public.alterations(boutique_id, status);

alter table public.alterations enable row level security;
drop policy if exists "alterations_rw" on public.alterations;
create policy "alterations_rw" on public.alterations for all to authenticated
  using (boutique_id = public.current_boutique_id())
  with check (boutique_id = public.current_boutique_id());
drop policy if exists "alterations_service" on public.alterations;
create policy "alterations_service" on public.alterations for all to service_role using (true) with check (true);

drop trigger if exists alterations_updated_at on public.alterations;
create trigger alterations_updated_at before update on public.alterations
  for each row execute function public.set_updated_at();

create or replace function public.emit_event_on_appointment_change()
returns trigger language plpgsql security definer as $$
begin
  insert into public.events (boutique_id, actor_type, event_name, payload_json)
  values (new.boutique_id, 'system',
    case when tg_op = 'INSERT' then 'appointment.created' else 'appointment.updated' end,
    jsonb_build_object('appointment_id', new.id, 'customer_id', new.customer_id,
                       'type', new.type, 'scheduled_at', new.scheduled_at, 'status', new.status));
  return new;
end; $$;
drop trigger if exists appointments_event on public.appointments;
create trigger appointments_event after insert or update on public.appointments
  for each row execute function public.emit_event_on_appointment_change();
