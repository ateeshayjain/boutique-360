-- Plan 1, Task 1.16 — RLS helper RPC + boutiques self-read policy
create or replace function public.set_boutique_id_from_user()
returns void language plpgsql security definer set search_path = public as $$
declare bid uuid;
begin
  select boutique_id into bid from public.staff_users where id = auth.uid() and active = true;
  if bid is null then raise exception 'no active staff record for user %', auth.uid(); end if;
  perform set_config('app.boutique_id', bid::text, true);
end;
$$;
grant execute on function public.set_boutique_id_from_user() to authenticated;

create policy "boutiques_self_read" on public.boutiques for select to authenticated
  using (id = (current_setting('app.boutique_id', true))::uuid);
