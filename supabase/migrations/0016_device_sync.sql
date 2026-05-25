-- Plan 1, Task 1.15 — device_sync_state (iPad offline-first sync)
create table public.device_sync_state (
  device_id uuid primary key,
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  staff_user_id uuid not null references public.staff_users(id) on delete cascade,
  last_synced_at timestamptz,
  last_event_id_seen uuid,
  app_version text,
  ios_version text,
  device_model text,
  registered_at timestamptz not null default now()
);
create index device_sync_staff_idx on public.device_sync_state(staff_user_id);

alter table public.device_sync_state enable row level security;
create policy "device_sync_self" on public.device_sync_state for all to authenticated
  using (staff_user_id = auth.uid())
  with check (staff_user_id = auth.uid());
create policy "device_sync_service" on public.device_sync_state for all to service_role using (true) with check (true);
