-- BACKFILLED 2026-07-31 from supabase_migrations.schema_migrations.
-- Applied to production 2026-05-26 (version 20260526092333).
-- RECORD of SQL that has already run — do not re-apply as a new migration.
--
-- ⚠️ Note for whoever reads this before a store submission: this seeded a
-- PLACEHOLDER GSTIN ('07AAACA0000A1Z5') and a placeholder address onto the
-- pilot boutique. `coalesce` means a real value entered in Settings is never
-- overwritten — but if nobody has entered one, invoices are being generated
-- against a fake GSTIN. Check before filing anything.

alter table public.boutiques add column if not exists address text;
alter table public.boutiques add column if not exists place_of_supply text;

update public.boutiques
set address = coalesce(address, 'Shop 12, Lajpat Nagar, New Delhi 110024'),
    place_of_supply = coalesce(place_of_supply, 'Delhi'),
    gstin = coalesce(gstin, '07AAACA0000A1Z5')  -- placeholder; owner replaces in Settings UI
where id = '00000000-0000-0000-0000-000000000001';
