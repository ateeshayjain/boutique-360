alter table public.orders
  add column if not exists design_id uuid references public.designs(id) on delete set null;

create table if not exists public.order_locks (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  order_id uuid not null unique references public.orders(id) on delete cascade,
  design_id uuid references public.designs(id) on delete set null,
  render_image_path text,
  fabric_code text,
  fabric_description text,
  measurement_id uuid references public.customer_measurements(id) on delete set null,
  price_breakup jsonb,               -- {"fabric": n, "work": n, "other": n}
  event_date date,                   -- frozen copy at lock time
  alteration_buffer_days int,        -- frozen copy
  must_finish_by date,               -- frozen computed copy
  advance_amount numeric not null,
  rush_accepted boolean not null default false,
  locked_at timestamptz not null default now()
);
alter table public.order_locks enable row level security;
-- Policy pair per migration 0010's rw pattern (NOT 0028's select-only pair —
-- the app must insert):
create policy "order_locks_rw" on public.order_locks for all to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid)
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "order_locks_service" on public.order_locks for all to service_role
  using (true) with check (true);

create table if not exists public.change_orders (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  order_id uuid not null references public.orders(id) on delete cascade,
  description text not null,
  price_delta numeric not null default 0,   -- pre-GST delta to subtotal; may be negative
  new_event_date date,                      -- null = unchanged
  created_at timestamptz not null default now()
);
create index if not exists change_orders_order_idx on public.change_orders(order_id, created_at);
alter table public.change_orders enable row level security;
-- APPEND-ONLY enforced at the DB: authenticated gets select + insert only
-- (no update/delete policies exist, so RLS denies them). Inserts normally
-- arrive via the invoker RPC, which runs under the same policies.
create policy "change_orders_select" on public.change_orders for select to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "change_orders_insert" on public.change_orders for insert to authenticated
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "change_orders_service" on public.change_orders for all to service_role
  using (true) with check (true);

-- Atomic lock: insert the lock row + patch orders.design_id in ONE
-- transaction (house rule: multi-row writes via RPC). jsonb payload =
-- NewOrderLock's encoded fields.
create or replace function public.lock_order(p_lock jsonb)
returns public.order_locks
language plpgsql
as $$
declare
  v_new public.order_locks;
  v_lock public.order_locks;
  v_order public.orders;
begin
  v_new := jsonb_populate_record(null::public.order_locks, p_lock);

  -- Read the order first: (a) integrity — the lock's boutique must match
  -- the order's (a mismatched payload must not create a cross-boutique
  -- lock row); (b) server-side status gate, symmetric with
  -- apply_change_order's lock check.
  select * into v_order from public.orders where id = v_new.order_id for update;
  if not found then raise exception 'order % not found', v_new.order_id; end if;
  if v_order.boutique_id is distinct from v_new.boutique_id then
    raise exception 'lock boutique does not match order boutique';
  end if;
  if v_order.status not in ('pending', 'confirmed') then
    raise exception 'order % is % — only pending/confirmed orders can be locked',
      v_new.order_id, v_order.status;
  end if;

  insert into public.order_locks
    (id, boutique_id, order_id, design_id, render_image_path, fabric_code,
     fabric_description, measurement_id, price_breakup, event_date,
     alteration_buffer_days, must_finish_by, advance_amount, rush_accepted,
     locked_at)
  values
    (coalesce(v_new.id, gen_random_uuid()), v_new.boutique_id, v_new.order_id,
     v_new.design_id, v_new.render_image_path, v_new.fabric_code,
     v_new.fabric_description, v_new.measurement_id, v_new.price_breakup,
     v_new.event_date, v_new.alteration_buffer_days, v_new.must_finish_by,
     coalesce(v_new.advance_amount, 0), coalesce(v_new.rush_accepted, false),
     coalesce(v_new.locked_at, now()))
  returning * into v_lock;
  -- (Explicit column list + coalesce — NEVER `insert select *` from
  -- jsonb_populate_record; see the 0028 RPC-repair lesson in api-rpcs.md.)

  if v_lock.design_id is not null then
    update public.orders set design_id = v_lock.design_id, updated_at = now()
     where id = v_lock.order_id;
  end if;
  return v_lock;
end;
$$;

-- Atomic CO application: insert CO + retarget order totals/event date.
-- GST recomputed at the ORDER'S EFFECTIVE RATE = gst_amount / nullif(subtotal, 0)
-- (orders store amounts, not a rate; zero-subtotal orders use rate 0).
create or replace function public.apply_change_order(
  p_order_id uuid,
  p_description text,
  p_price_delta numeric default 0,
  p_new_event_date date default null
) returns public.change_orders
language plpgsql
as $$
declare
  v_order public.orders;
  v_rate numeric;
  v_new_subtotal numeric;
  v_new_gst numeric;
  v_co public.change_orders;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'order % not found', p_order_id; end if;

  -- Precondition: change orders exist only for LOCKED orders. The UI gates
  -- this too; the RPC is the enforcement of record.
  if not exists (select 1 from public.order_locks where order_id = p_order_id) then
    raise exception 'order % is not locked — change orders apply to locked orders only', p_order_id;
  end if;

  v_new_subtotal := v_order.subtotal + p_price_delta;
  if v_new_subtotal < 0 then
    raise exception 'change order would make subtotal negative (% + % = %)',
      v_order.subtotal, p_price_delta, v_new_subtotal;
  end if;

  v_rate := case when v_order.subtotal > 0
                 then v_order.gst_amount / v_order.subtotal else 0 end;
  v_new_gst := round(v_new_subtotal * v_rate, 2);

  insert into public.change_orders (boutique_id, order_id, description, price_delta, new_event_date)
  values (v_order.boutique_id, p_order_id, p_description, p_price_delta, p_new_event_date)
  returning * into v_co;

  update public.orders
     set subtotal   = v_new_subtotal,
         gst_amount = v_new_gst,
         -- Reuse the already-rounded GST so total = subtotal + gst + shipping
         -- holds exactly (no independent rounding drift).
         total      = v_new_subtotal + v_new_gst + coalesce(shipping, 0),
         event_date = coalesce(p_new_event_date, event_date),
         updated_at = now()
   where id = p_order_id;

  return v_co;
end;
$$;
