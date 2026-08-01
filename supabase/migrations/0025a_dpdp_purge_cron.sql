-- BACKFILLED 2026-07-31 from supabase_migrations.schema_migrations.
-- Applied to production 2026-05-28 as `dpdp_purge_cron` (version 20260528105120).
-- This file is a RECORD of SQL that has already run — do not re-apply it as a
-- new migration. Numbered 0025a because it landed between 0025_audit_fixes and
-- 0026_design_reference_image, and renumbering shipped files would be worse.
--
-- ⚠️ The comments below are WRONG and are preserved verbatim because this is a
-- historical record. `'30 21 * * *'` is 21:30 UTC = 03:00 IST, not the
-- "02:30 IST = 21:00 UTC" the comments claim. That contradiction is the origin
-- of the wrong purge time that propagated into CLAUDE.md, architecture.md,
-- deployment.md, api-rpcs.md, app-map.md, dpdp-compliance.md and the
-- customer-facing privacy policy. Those are corrected; this file is not,
-- because it documents what actually ran.
--
-- Verified live 2026-07-31: job `dpdp-purge-tryons` active, 64 runs, all
-- succeeded, most recent 2026-07-30 21:30 UTC.

-- Enable cron + http (pg_net) extensions if not already.
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Daily 02:30 IST = 21:00 UTC. Calls the purge-expired-tryons Edge Function.
-- The service role key lives in Vault to avoid leaking in pg_cron job source.
-- For pilot: hardcode anon key fetch. In prod replace with Vault.

do $$
declare
  v_url text := 'https://tdnwdlrkbrtoxjzcgusg.supabase.co/functions/v1/purge-expired-tryons';
begin
  -- Drop existing job if re-running this migration
  if exists (select 1 from cron.job where jobname = 'dpdp-purge-tryons') then
    perform cron.unschedule('dpdp-purge-tryons');
  end if;

  perform cron.schedule(
    'dpdp-purge-tryons',
    '30 21 * * *',  -- 21:00 UTC daily = 02:30 IST
    format($job$
      select net.http_post(
        url := %L,
        headers := jsonb_build_object('Content-Type', 'application/json')
      );
    $job$, v_url)
  );
end $$;
