-- 0033 — fix the cap-breach message, and clear the row 0032's verification left.
--
-- Postgres RAISE does not support printf precision. '$%.2f' does not format a
-- number to 2dp; it substitutes the value and then emits a literal '.2f':
--
--   "Daily AI cost ceiling of $5.0.2f exceeded ($99.0010.2f spent today)"
--
-- Inherited from 0025d and invisible while the RPC 403'd before ever reaching
-- the raise. It matters now, because AICostMeter surfaces the real P0001
-- message to the owner instead of a fixed string. `round()` on the numerics
-- is the fix.

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
    raise exception 'Daily AI limit of $% reached ($% used today)',
      round(p_daily_cap_usd, 2), round(v_row.cost_estimate_usd, 2)
      using errcode = 'P0001';
  end if;

  return query select v_row.calls_count, v_row.cost_estimate_usd, p_daily_cap_usd;
end;
$func$;

revoke execute on function public.record_ai_usage(uuid, numeric, numeric) from anon;
grant  execute on function public.record_ai_usage(uuid, numeric, numeric) to authenticated;

-- Remove the row 0032's verification call created (0.001 of a $5 cap, but it
-- is test data and it is production).
delete from public.ai_usage_daily
 where boutique_id = '00000000-0000-0000-0000-000000000001'
   and usage_date = current_date
   and calls_count = 1
   and cost_estimate_usd = 0.0010;
