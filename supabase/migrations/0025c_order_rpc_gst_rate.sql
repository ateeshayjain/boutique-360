-- BACKFILLED 2026-07-31 from supabase_migrations.schema_migrations.
-- Applied to production 2026-05-28 as `order_rpc_gst_rate` (version 20260528112008).
-- RECORD of SQL that has already run — do not re-apply as a new migration.
--
-- SUPERSEDED by 0028_event_slack_karigar.sql. This version contains the
-- `insert into orders select * from jsonb_populate_record(...)` pattern that
-- writes explicit NULLs for any key absent from p_order, bypassing the
-- column defaults. It was latently broken in production until 0028 replaced
-- it with an explicit column list plus coalesce. Kept verbatim so the defect's
-- history is legible rather than quietly erased.

-- Update create_order_with_items to handle the new gst_rate column.
create or replace function public.create_order_with_items(
  p_order jsonb,
  p_items jsonb,
  p_source_inquiry_id uuid default null
) returns public.orders
language plpgsql
security invoker
as $func$
declare
  v_order public.orders;
  v_item jsonb;
begin
  insert into public.orders
  select * from jsonb_populate_record(null::public.orders, p_order)
  returning * into v_order;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    insert into public.order_items (
      order_id, boutique_id, product_id, variant_id,
      qty, unit_price, gst_rate, gst_amount, line_description
    ) values (
      v_order.id,
      (v_item->>'boutique_id')::uuid,
      nullif(v_item->>'product_id','')::uuid,
      nullif(v_item->>'variant_id','')::uuid,
      (v_item->>'qty')::int,
      (v_item->>'unit_price')::numeric,
      nullif(v_item->>'gst_rate','')::numeric,
      (v_item->>'gst_amount')::numeric,
      v_item->>'line_description'
    );
  end loop;

  if p_source_inquiry_id is not null then
    update public.inquiries
       set converted_order_id = v_order.id,
           status = 'confirmed',
           updated_at = now()
     where id = p_source_inquiry_id;
  end if;

  return v_order;
end;
$func$;
