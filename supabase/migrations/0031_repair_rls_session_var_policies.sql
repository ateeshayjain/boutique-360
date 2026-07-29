-- 0031 — REPAIR: replace the dead session-variable RLS idiom with
-- current_boutique_id() on every table created after migration 0017.
--
-- ROOT CAUSE
-- Two policy idioms exist in this database:
--   working:  boutique_id = current_boutique_id()
--             — SECURITY DEFINER function reading staff_users via auth.uid();
--               self-contained, evaluates correctly on every request.
--   broken:   boutique_id = (current_setting('app.boutique_id', true))::uuid
--             — a TRANSACTION-LOCAL session variable that nothing ever sets.
--               set_boutique_id_from_user() (0017) exists but has zero client
--               call sites, and even if called could not persist past its own
--               transaction. The expression evaluates to NULL, so the
--               comparison is never true and the policy denies everything.
--
-- Migration 0017 moved all THEN-EXISTING tables to the function form. Tables
-- created afterwards that copied the older pattern out of a pre-0017
-- migration file inherited the dead idiom:
--   * order_locks    (0029, R3)  — the Lock feature would 403 in the app
--   * change_orders  (0029, R3)  — change orders would 403 in the app
--   * reminder_log   (0030, R4a) — never exercised yet
--
-- Neither surfaced because all three tables were empty and the live smoke
-- tests ran through MCP as service_role, which bypasses RLS entirely.
-- Verified with a real authenticated demo-user session: insert → 403 42501,
-- select → [] on all three, while customers/orders/events behave correctly.
--
-- Append-only shapes are preserved exactly: order_locks keeps its rw pair;
-- change_orders and reminder_log keep select+insert only (no update/delete
-- policy ⇒ RLS continues to deny those).

-- ─── order_locks (R3): read/write pair
drop policy if exists "order_locks_rw" on public.order_locks;
create policy "order_locks_rw" on public.order_locks for all to authenticated
  using (boutique_id = current_boutique_id())
  with check (boutique_id = current_boutique_id());

-- ─── change_orders (R3): append-only (select + insert)
drop policy if exists "change_orders_select" on public.change_orders;
drop policy if exists "change_orders_insert" on public.change_orders;
create policy "change_orders_select" on public.change_orders for select to authenticated
  using (boutique_id = current_boutique_id());
create policy "change_orders_insert" on public.change_orders for insert to authenticated
  with check (boutique_id = current_boutique_id());

-- ─── reminder_log (R4a): append-only (select + insert)
drop policy if exists "reminder_log_select" on public.reminder_log;
drop policy if exists "reminder_log_insert" on public.reminder_log;
create policy "reminder_log_select" on public.reminder_log for select to authenticated
  using (boutique_id = current_boutique_id());
create policy "reminder_log_insert" on public.reminder_log for insert to authenticated
  with check (boutique_id = current_boutique_id());

-- ─── Guard against a repeat: boutiques_self_read (0017) uses the same dead
-- idiom. It is currently masked by another policy, but fix it here so the
-- pattern is gone from the schema entirely.
drop policy if exists "boutiques_self_read" on public.boutiques;
create policy "boutiques_self_read" on public.boutiques for select to authenticated
  using (id = current_boutique_id());
