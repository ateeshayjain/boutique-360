-- 0028 — R1 slack inputs + R4d karigar link plumbing + RPC repair.

-- ─── R1: event anchoring on orders
alter table public.orders
  add column if not exists event_date date,
  add column if not exists alteration_buffer_days int not null default 7;

comment on column public.orders.event_date is
  'Customer''s occasion date (wedding/reception). Null = no hard deadline; slack undefined.';
comment on column public.orders.alteration_buffer_days is
  'Days reserved between production completion and the event for fittings/alterations.';

-- ─── R4d: karigar magic-link capability token + progress events
alter table public.job_cards
  add column if not exists share_token uuid not null default gen_random_uuid();
create unique index if not exists job_cards_share_token_idx on public.job_cards(share_token);

create table if not exists public.job_card_events (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  job_card_id uuid not null references public.job_cards(id) on delete cascade,
  event text not null check (event in ('started','stitching_done','ready')),
  wip_photo_path text,
  created_at timestamptz not null default now()
);
create index if not exists job_card_events_card_idx on public.job_card_events(job_card_id, created_at);
alter table public.job_card_events enable row level security;
create policy "job_card_events_owner_read" on public.job_card_events for select to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "job_card_events_service" on public.job_card_events for all to service_role
  using (true) with check (true);

-- ─── REPAIR + extend create_order_with_items.
-- The previous version inserted the header via
--   insert into orders select * from jsonb_populate_record(null::orders, p_order)
-- jsonb_populate_record yields explicit NULL for every key absent from the
-- payload, and `insert ... select *` writes those NULLs, BYPASSING column
-- defaults — a payload without "id" violates the PK NOT NULL, and after this
-- migration a payload without "alteration_buffer_days" (any already-installed
-- app build) would violate its NOT NULL too. Fix: explicit column list with
-- coalesce() for every defaulted column. Items loop + inquiry link preserved
-- from the DEPLOYED version (which already carries gst_rate — deployed body
-- had drifted ahead of the 0025 file).
create or replace function public.create_order_with_items(
  p_order jsonb,
  p_items jsonb,
  p_source_inquiry_id uuid default null
) returns public.orders
language plpgsql
as $$
declare
  v_new public.orders;
  v_order public.orders;
  v_item jsonb;
begin
  v_new := jsonb_populate_record(null::public.orders, p_order);

  insert into public.orders
    (id, boutique_id, order_number, customer_id, status, subtotal,
     gst_amount, shipping, total, currency, shipping_address_json,
     tracking_url, tracking_courier, magic_link_token, fulfillment_method,
     placed_at, event_date, alteration_buffer_days, created_at, updated_at)
  values
    (coalesce(v_new.id, gen_random_uuid()),
     v_new.boutique_id,
     v_new.order_number,
     v_new.customer_id,
     coalesce(v_new.status, 'pending'),
     coalesce(v_new.subtotal, 0),
     coalesce(v_new.gst_amount, 0),
     v_new.shipping,
     coalesce(v_new.total, 0),
     coalesce(v_new.currency, 'INR'),
     v_new.shipping_address_json,
     v_new.tracking_url,
     v_new.tracking_courier,
     v_new.magic_link_token,
     coalesce(v_new.fulfillment_method, 'pickup'),
     v_new.placed_at,
     v_new.event_date,
     coalesce(v_new.alteration_buffer_days, 7),
     coalesce(v_new.created_at, now()),
     coalesce(v_new.updated_at, now()))
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
$$;
