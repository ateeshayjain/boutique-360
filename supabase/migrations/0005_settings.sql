-- Plan 1, Task 1.6 — settings (per-boutique config, optionally pgsodium-encrypted)
create table public.settings (
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  key text not null,
  value_json jsonb,
  value_encrypted bytea,
  is_secret boolean not null default false,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  primary key (boutique_id, key),
  check ((is_secret = false and value_json is not null and value_encrypted is null)
      or (is_secret = true  and value_encrypted is not null and value_json is null))
);

alter table public.settings enable row level security;
create policy "settings_read" on public.settings for select to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid);
create policy "settings_service" on public.settings for all to service_role using (true) with check (true);
