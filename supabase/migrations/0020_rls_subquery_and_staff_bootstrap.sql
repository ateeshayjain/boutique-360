-- BACKFILLED 2026-07-31 from supabase_migrations.schema_migrations.
-- Applied to production 2026-05-25 (version 20260525131027).
-- RECORD of SQL that has already run — do not re-apply as a new migration.
--
-- THE most important migration to read before writing any RLS policy.
-- It replaced the `current_setting('app.boutique_id')` GUC pattern with
-- `current_boutique_id()` because the GUC does not survive PostgREST's
-- connection pool — it is never set, so any policy using it can never match.
--
-- That warning was later ignored: migrations 0029 (order_locks,
-- change_orders) and 0030 (reminder_log) were written with the dead GUC
-- pattern, apparently copied from pre-0020 files. R3's Lock feature therefore
-- shipped non-functional and stayed that way until 0031 repaired it. If you
-- are writing a policy, copy from THIS file, not from anything numbered below
-- 0020.
--
-- ⚠️ Also note `handle_new_auth_user`: ANY new auth signup is auto-bound to
-- the hardcoded dev boutique, as 'owner' if they are the first row and 'staff'
-- otherwise. Fine for a single-tenant pilot; it is a tenancy hole the moment a
-- second boutique exists.

-- ────────────────────────────────────────────────────────────────────────
-- 0020: Fix RLS pattern (GUC → subquery) + auto-bootstrap staff_users on signup
-- ────────────────────────────────────────────────────────────────────────
-- The original GUC-based RLS (current_setting('app.boutique_id')) doesn't
-- survive across PostgREST's connection pool. Replacing with a subquery
-- pattern that uses auth.uid() (always present in JWT) to derive the
-- caller's boutique_id from staff_users.

-- Helper: get current user's boutique_id (cached per-statement)
create or replace function public.current_boutique_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select boutique_id from public.staff_users where id = auth.uid() and active = true
$$;
grant execute on function public.current_boutique_id() to authenticated, anon;

-- Replace all "_rw" policies that used the GUC pattern with current_boutique_id()
do $$
declare
  t text;
  policy_name text;
begin
  for t in select unnest(array[
    'events','settings','customers','customer_profiles','customer_measurements',
    'customer_relationships','important_dates','loyalty_tiers','customer_tier_history',
    'products','product_variants','orders','order_items','payments','invoices',
    'inquiries','inquiry_messages','fabrics','designs','design_fabrics',
    'design_renders','design_tryons','vto_sessions',
    'message_templates','conversations','messages',
    'automation_journeys','journey_runs'
  ]) loop
    -- drop the old policies (both rw and any read-only variants)
    for policy_name in
      select polname::text from pg_policy
      where polrelid = ('public.' || t)::regclass
        and polname not like '%service%'
        and polname not like '%public_%'
        and polname not like '%self%'
        and polname not like '%magic_link%'
    loop
      execute format('drop policy if exists %I on public.%I', policy_name, t);
    end loop;
    -- create new policy using subquery
    execute format(
      'create policy "%I_rw" on public.%I for all to authenticated using (boutique_id = public.current_boutique_id()) with check (boutique_id = public.current_boutique_id())',
      t, t
    );
  end loop;
end $$;

-- boutiques: read your own boutique
drop policy if exists "boutiques_read_own" on public.boutiques;
drop policy if exists "boutiques_self_read" on public.boutiques;
create policy "boutiques_self_read" on public.boutiques for select to authenticated
  using (id = public.current_boutique_id());

-- events: keep insert-allowed policy
drop policy if exists "events_insert" on public.events;
create policy "events_insert_own" on public.events for insert to authenticated
  with check (boutique_id = public.current_boutique_id());

-- ────────────────────────────────────────────────────────────────────────
-- Staff bootstrap: when a new user signs up (first magic-link), create a
-- staff_users row binding them to the dev boutique. First user = owner,
-- subsequent users = staff. v1 single-tenant.
-- ────────────────────────────────────────────────────────────────────────
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  dev_boutique_id uuid := '00000000-0000-0000-0000-000000000001';
  existing_count int;
  new_role public.staff_role;
begin
  -- If staff_users row already exists for this auth user, do nothing
  if exists (select 1 from public.staff_users where id = new.id) then
    return new;
  end if;

  select count(*) into existing_count from public.staff_users where boutique_id = dev_boutique_id;
  new_role := case when existing_count = 0 then 'owner'::public.staff_role else 'staff'::public.staff_role end;

  insert into public.staff_users (id, boutique_id, name, email, role, active)
  values (
    new.id,
    dev_boutique_id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    new.email,
    new_role,
    true
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();
