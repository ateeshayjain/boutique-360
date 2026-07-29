-- 0030 — R4a reminder dedup log. Append-only: a handled reminder stays handled.
create table if not exists public.reminder_log (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  kind text not null check (kind in ('fitting','payment','ready')),
  subject_id uuid not null,          -- appointment id (fitting) | order id (payment/ready)
  for_date date not null,
  created_at timestamptz not null default now(),
  unique (boutique_id, kind, subject_id, for_date)
);
create index if not exists reminder_log_boutique_date_idx
  on public.reminder_log(boutique_id, for_date);
alter table public.reminder_log enable row level security;
-- Append-only for the app (same shape as change_orders in 0029): select +
-- insert only. No update/delete policy → RLS denies them.
create policy "reminder_log_select" on public.reminder_log for select to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "reminder_log_insert" on public.reminder_log for insert to authenticated
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "reminder_log_service" on public.reminder_log for all to service_role
  using (true) with check (true);
