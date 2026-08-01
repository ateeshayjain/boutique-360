-- BACKFILLED 2026-07-31 from supabase_migrations.schema_migrations.
-- Applied to production 2026-05-28 as `audit_phase3_constraints_costceil`
-- (version 20260528121350).
-- RECORD of SQL that has already run — do not re-apply as a new migration.
--
-- ⚠️ THIS MIGRATION SHIPPED A LIVE DEFECT. See the note at the bottom.

-- CHECK constraints surfaced by testing audit
do $$ begin
  -- order_items.qty must be > 0 (no zero-quantity lines)
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.order_items'::regclass and conname = 'order_items_qty_positive'
  ) then
    alter table public.order_items
      add constraint order_items_qty_positive check (qty > 0);
  end if;

  -- payments.amount must be > 0 (zero payments are noise)
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.payments'::regclass and conname = 'payments_amount_positive'
  ) then
    alter table public.payments
      add constraint payments_amount_positive check (amount > 0);
  end if;

  -- order_items.unit_price must be >= 0 (allow free promotional lines)
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.order_items'::regclass and conname = 'order_items_unit_price_nonneg'
  ) then
    alter table public.order_items
      add constraint order_items_unit_price_nonneg check (unit_price >= 0);
  end if;
end $$;

-- Gemini cost ceiling (Testing audit gap)
-- Per-boutique daily counter. RPC increments + checks the cap atomically.
create table if not exists public.ai_usage_daily (
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  usage_date date not null,
  calls_count int not null default 0,
  cost_estimate_usd numeric(10,4) not null default 0,
  primary key (boutique_id, usage_date)
);

comment on table public.ai_usage_daily is
  'Per-boutique per-day AI cost counter. Used to enforce a soft daily ceiling so runaway prompts cannot rack unbounded Gemini bills.';

alter table public.ai_usage_daily enable row level security;

create policy ai_usage_daily_read on public.ai_usage_daily
  for select using (boutique_id = current_boutique_id());

-- Atomic check-and-increment. Returns the row's new totals so the caller knows where it stands.
-- If cap exceeded, raises a friendly error that PostgREST surfaces as 400.
create or replace function public.record_ai_usage(
  p_boutique_id uuid,
  p_cost_estimate_usd numeric,
  p_daily_cap_usd numeric default 5.0
) returns table (calls_count int, cost_estimate_usd numeric, daily_cap_usd numeric)
language plpgsql
security invoker
as $func$
declare
  v_row public.ai_usage_daily;
begin
  insert into public.ai_usage_daily (boutique_id, usage_date, calls_count, cost_estimate_usd)
       values (p_boutique_id, current_date, 1, p_cost_estimate_usd)
  on conflict (boutique_id, usage_date) do update
        set calls_count = ai_usage_daily.calls_count + 1,
            cost_estimate_usd = ai_usage_daily.cost_estimate_usd + p_cost_estimate_usd
   returning * into v_row;

  if v_row.cost_estimate_usd > p_daily_cap_usd then
    raise exception 'Daily AI cost ceiling of $%.2f exceeded ($%.2f spent today)',
      p_daily_cap_usd, v_row.cost_estimate_usd
      using errcode = 'P0001';
  end if;

  return query select v_row.calls_count, v_row.cost_estimate_usd, p_daily_cap_usd;
end;
$func$;

-- ---------------------------------------------------------------------------
-- ⚠️ DEFECT SHIPPED HERE — found 2026-07-31, fixed by 0032.
--
-- `ai_usage_daily` has RLS enabled with a SELECT policy ONLY, and
-- `record_ai_usage` is `security invoker`. So the INSERT above runs as the
-- authenticated user against a table with no INSERT policy and is rejected:
--
--   HTTP 403 — "new row violates row-level security policy for
--               table \"ai_usage_daily\""
--
-- Verified 2026-07-31 by calling the RPC as the authenticated demo user.
-- `ai_usage_daily` contained ZERO rows — the counter never recorded a call.
--
-- Impact: `AICostMeter.checkCeiling` runs BEFORE every Gemini request, so
-- EVERY AI feature (render, virtual try-on, tailor brief, style suggestions)
-- failed in production. Worse, `checkCeiling` catches any error and rethrows
-- it as "Daily AI cost ceiling reached — try again after midnight", so the
-- owner was told they had hit a spending cap they had never reached.
--
-- Root cause is the same as the dead policies repaired by 0031: an RLS policy
-- set that was never exercised as an authenticated user. Verifying through the
-- Supabase MCP does not catch it — MCP runs as service_role, which bypasses
-- RLS entirely.
-- ---------------------------------------------------------------------------
