-- Plan 1, Task 1.16 — updated_at trigger + event-emit-on-status-change triggers
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end; $$;

do $$
declare t text;
begin
  for t in select unnest(array[
    'boutiques','staff_users','settings','customers','customer_profiles',
    'loyalty_tiers','products','product_variants','orders','payments',
    'inquiries','designs','message_templates','conversations','automation_journeys'
  ]) loop
    execute format('drop trigger if exists %I_updated_at on public.%I', t, t);
    execute format('create trigger %I_updated_at before update on public.%I for each row execute function public.set_updated_at()', t, t);
  end loop;
end $$;

create or replace function public.emit_event_on_order_status_change()
returns trigger language plpgsql security definer as $$
begin
  if new.status is distinct from old.status then
    insert into public.events (boutique_id, actor_type, event_name, payload_json)
    values (new.boutique_id, 'system', 'order.status_changed',
      jsonb_build_object('order_id', new.id, 'order_number', new.order_number,
                         'from', old.status, 'to', new.status, 'customer_id', new.customer_id));
  end if;
  return new;
end; $$;
create trigger orders_status_event after update on public.orders
  for each row execute function public.emit_event_on_order_status_change();

create or replace function public.emit_event_on_inquiry_status_change()
returns trigger language plpgsql security definer as $$
begin
  if new.status is distinct from old.status then
    insert into public.events (boutique_id, actor_type, event_name, payload_json)
    values (new.boutique_id, 'system', 'inquiry.status_changed',
      jsonb_build_object('inquiry_id', new.id, 'from', old.status, 'to', new.status,
                         'customer_id', new.customer_id));
  end if;
  return new;
end; $$;
create trigger inquiries_status_event after update on public.inquiries
  for each row execute function public.emit_event_on_inquiry_status_change();
