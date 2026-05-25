-- Plan 1, Task 1.5 — events (append-only audit/event stream)
create table public.events (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  actor_type text not null check (actor_type in ('staff','customer','system','webhook','ipad')),
  actor_id uuid,
  event_name text not null,
  payload_json jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);
create index events_boutique_time_idx on public.events(boutique_id, occurred_at desc);
create index events_name_idx on public.events(event_name);
create index events_payload_gin on public.events using gin (payload_json);

alter table public.events enable row level security;
create policy "events_read" on public.events for select to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "events_insert" on public.events for insert to authenticated
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "events_service" on public.events for all to service_role using (true) with check (true);
