-- 0032 — repair `record_ai_usage`, which has 403'd for every authenticated
-- caller since it shipped in 0025d (2026-05-28).
--
-- The defect: `ai_usage_daily` has RLS enabled with a SELECT policy only, and
-- `record_ai_usage` was `security invoker`, so its INSERT ran as the calling
-- user against a table with no INSERT policy and was rejected:
--
--   HTTP 403 — 42501 "new row violates row-level security policy
--                     for table ai_usage_daily"
--
-- `AICostMeter.checkCeiling` runs before EVERY Gemini request, so this took
-- down every AI feature in the app: render, virtual try-on, tailor brief and
-- style suggestions. `ai_usage_daily` held zero rows — the counter never
-- recorded a single call.
--
-- WHY security definer AND NOT an INSERT/UPDATE policy:
-- the feature's whole point is a counter the iPad cannot tamper with
-- ("server-side counter so the limit is tamper-proof from the iPad" —
-- AICostMeter.swift). Granting the client INSERT/UPDATE on ai_usage_daily
-- would let it zero its own usage and walk past the cap. `security definer`
-- keeps writes exclusive to this function, so the SELECT-only policy stays
-- exactly right: clients may read their usage, never write it.
--
-- Because `security definer` bypasses RLS, the boutique check that RLS would
-- have performed is now made explicitly inside the function — otherwise any
-- authenticated user could inflate (or, by passing someone else's id, evade)
-- another boutique's counter.
--
-- `search_path` is pinned: a definer function without it can be hijacked via a
-- caller-controlled search_path.
--
-- Behaviour preserved deliberately: raising on cap breach rolls back the
-- increment in the same transaction, so a blocked call is not billed to the
-- counter. That is correct — the Gemini request never happened.

create or replace function public.record_ai_usage(
  p_boutique_id uuid,
  p_cost_estimate_usd numeric,
  p_daily_cap_usd numeric default 5.0
) returns table (calls_count int, cost_estimate_usd numeric, daily_cap_usd numeric)
language plpgsql
security definer
set search_path = public, pg_temp
as $func$
declare
  v_row public.ai_usage_daily;
  v_caller_boutique uuid;
begin
  -- RLS is bypassed here, so scope the write by hand.
  v_caller_boutique := public.current_boutique_id();

  if v_caller_boutique is null then
    raise exception 'No active staff row for this user'
      using errcode = '42501';
  end if;

  if p_boutique_id is distinct from v_caller_boutique then
    raise exception 'Cannot record AI usage for another boutique'
      using errcode = '42501';
  end if;

  insert into public.ai_usage_daily (boutique_id, usage_date, calls_count, cost_estimate_usd)
       values (v_caller_boutique, current_date, 1, p_cost_estimate_usd)
  on conflict (boutique_id, usage_date) do update
        set calls_count = ai_usage_daily.calls_count + 1,
            cost_estimate_usd = ai_usage_daily.cost_estimate_usd + p_cost_estimate_usd
   returning * into v_row;

  if v_row.cost_estimate_usd > p_daily_cap_usd then
    -- P0001 is the contract with AICostMeter: this error, and only this
    -- error, means the cap was genuinely reached.
    raise exception 'Daily AI cost ceiling of $%.2f exceeded ($%.2f spent today)',
      p_daily_cap_usd, v_row.cost_estimate_usd
      using errcode = 'P0001';
  end if;

  return query select v_row.calls_count, v_row.cost_estimate_usd, p_daily_cap_usd;
end;
$func$;

revoke execute on function public.record_ai_usage(uuid, numeric, numeric) from anon;
grant  execute on function public.record_ai_usage(uuid, numeric, numeric) to authenticated;
