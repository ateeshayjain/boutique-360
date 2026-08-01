-- BACKFILLED 2026-07-31 from supabase_migrations.schema_migrations.
-- Applied to production 2026-05-28 as `audit_fixes_phase2` (version 20260528111712).
-- RECORD of SQL that has already run — do not re-apply as a new migration.
--
-- Origin of two rules CLAUDE.md still enforces: boutiques.default_gst_rate
-- (no hardcoded 5%) and order_items.gst_rate as the per-line source of truth,
-- which is why InvoicePDFGenerator reads the stored rate instead of inferring
-- it from gst_amount.

-- L2: per-boutique default GST rate (replaces the 5.0 hardcode)
alter table public.boutiques
  add column if not exists default_gst_rate numeric(5,2) not null default 5.0;

comment on column public.boutiques.default_gst_rate is
  'Default GST percentage to suggest when creating new orders. Boutiques in specific HSN categories may use 12 or 18.';

-- H13: explicit gst_rate per line item — eliminates the reverse-engineered
-- rate inference in InvoicePDFGenerator and supports mixed-rate orders.
alter table public.order_items
  add column if not exists gst_rate numeric(5,2);

comment on column public.order_items.gst_rate is
  'GST percentage on this line. Source of truth — gst_amount can be recomputed from (qty * unit_price * gst_rate / 100).';

-- Backfill existing rows: reverse-engineer from gst_amount / (qty * unit_price)
update public.order_items
   set gst_rate = round(case
                          when qty * unit_price > 0
                            then (gst_amount / (qty * unit_price)) * 100
                          else 5.0
                        end, 2)
 where gst_rate is null;
