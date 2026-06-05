-- Audit pass 2026-05-26 — fixes for B2, B6, M12, L6.
-- Run via supabase MCP `apply_migration`.

-- ─── B2: persist (bucket, path) for design_tryons too (mirror what 0022 did for renders/sketches)
alter table public.design_tryons
  add column if not exists customer_photo_path text,
  add column if not exists result_image_path text;

comment on column public.design_tryons.customer_photo_path is
  'Canonical path inside customer-photos bucket. Regenerate signed URL on read; do not persist URL.';
comment on column public.design_tryons.result_image_path is
  'Canonical path inside vto-results bucket. result_image_url is also stable here (public bucket) but path is the source of truth.';

-- ─── B6: atomic order create (header + items + optional inquiry link) in one transaction
-- Returns the created order row. PostgREST will surface a Postgres exception cleanly
-- if anything inside fails — the entire insert rolls back.
create or replace function public.create_order_with_items(
  p_order jsonb,
  p_items jsonb,
  p_source_inquiry_id uuid default null
) returns public.orders
language plpgsql
security invoker
as $$
declare
  v_order public.orders;
  v_item jsonb;
begin
  -- Insert the order header. jsonb→row coercion lets the client pass a single payload.
  insert into public.orders
  select * from jsonb_populate_record(null::public.orders, p_order)
  returning * into v_order;

  -- Insert each line item, stamped with the new order_id.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    insert into public.order_items (
      order_id, boutique_id, product_id, variant_id,
      qty, unit_price, gst_amount, line_description
    ) values (
      v_order.id,
      (v_item->>'boutique_id')::uuid,
      nullif(v_item->>'product_id','')::uuid,
      nullif(v_item->>'variant_id','')::uuid,
      (v_item->>'qty')::int,
      (v_item->>'unit_price')::numeric,
      (v_item->>'gst_amount')::numeric,
      v_item->>'line_description'
    );
  end loop;

  -- Optionally link a converting inquiry.
  if p_source_inquiry_id is not null then
    update public.inquiries
       set converted_order_id = v_order.id,
           status = 'confirmed',
           updated_at = now()
     where id = p_source_inquiry_id;
  end if;

  return v_order;
end;
$$;

-- ─── M12: race-safe alteration round numbers (same pattern as orders/jobcards)
create or replace function public.next_alteration_round(p_order_id uuid)
returns int
language plpgsql
security invoker
as $$
declare
  v_next int;
begin
  -- FOR UPDATE locks the rows so concurrent calls serialize.
  select coalesce(max(round_number), 0) + 1 into v_next
    from public.alterations
   where order_id = p_order_id
   for update;
  return v_next;
end;
$$;

-- ─── L6: inquiry numbers via shared boutique_sequences (eliminate random-collision risk)
-- No DDL needed — boutique_sequences already exists from 0022. The Swift code switches
-- from Int.random to rpc('next_sequence_value', p_sequence_name: 'inquiries-YYYY').
