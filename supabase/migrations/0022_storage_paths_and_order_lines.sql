-- BACKFILLED 2026-07-31 from supabase_migrations.schema_migrations.
-- Applied to production 2026-05-26 (version 20260526092119).
-- RECORD of SQL that has already run — do not re-apply as a new migration.
--
-- Origin of the (bucket, path) persistence rule in CLAUDE.md: signed URLs
-- expire in an hour, so the *_path columns are the source of truth and the
-- *_url columns are cache.
--
-- Worth reading as the CORRECT pattern for a privileged RPC:
-- `next_sequence_value` is `security definer` with a pinned `search_path`, an
-- explicit grant to `authenticated`, and RLS policies carrying `with check`
-- for both service_role and authenticated. `record_ai_usage` in 0025d does
-- none of that and 403s in production as a result — the right shape already
-- existed in this codebase two migrations earlier.

-- Fix: store stable (bucket, path) for private assets, not 1h-expiring signed URLs.
-- Keep the *_url columns for backward compat but treat them as cache, not source of truth.

alter table public.designs        add column if not exists sketch_image_path text;
alter table public.design_renders add column if not exists result_image_path text;
alter table public.design_tryons  add column if not exists customer_photo_path text;
alter table public.design_tryons  add column if not exists result_image_path text;
alter table public.fabrics        add column if not exists photo_path text;

-- Order items need free-text description for invoice lines (currently dropped on insert)
alter table public.order_items    add column if not exists line_description text;

-- Boutique-scoped order number sequence — race-safe alternative to count+1.
-- Per-boutique counter via a small table + atomic update returning next value.
create table if not exists public.boutique_sequences (
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  sequence_name text not null,
  current_value bigint not null default 0,
  primary key (boutique_id, sequence_name)
);

alter table public.boutique_sequences enable row level security;
drop policy if exists "boutique_sequences_service" on public.boutique_sequences;
create policy "boutique_sequences_service" on public.boutique_sequences
  for all to service_role using (true) with check (true);
drop policy if exists "boutique_sequences_rw" on public.boutique_sequences;
create policy "boutique_sequences_rw" on public.boutique_sequences
  for all to authenticated
  using (boutique_id = public.current_boutique_id())
  with check (boutique_id = public.current_boutique_id());

create or replace function public.next_sequence_value(
  p_boutique_id uuid,
  p_sequence_name text
) returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  next_val bigint;
begin
  insert into public.boutique_sequences (boutique_id, sequence_name, current_value)
  values (p_boutique_id, p_sequence_name, 1)
  on conflict (boutique_id, sequence_name)
  do update set current_value = boutique_sequences.current_value + 1
  returning current_value into next_val;
  return next_val;
end;
$$;
grant execute on function public.next_sequence_value(uuid, text) to authenticated;

-- Seed the sequence at the current max so existing orders don't get re-used numbers
insert into public.boutique_sequences (boutique_id, sequence_name, current_value)
select boutique_id,
       'orders-' || to_char(now(), 'YYYY'),
       count(*)
from public.orders
where order_number like 'BTQ-' || to_char(now(), 'YYYY') || '-%'
group by boutique_id
on conflict (boutique_id, sequence_name) do update set current_value = greatest(boutique_sequences.current_value, excluded.current_value);
