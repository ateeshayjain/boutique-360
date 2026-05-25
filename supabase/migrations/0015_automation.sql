-- Plan 1, Task 1.15 — automation_journeys + journey_runs
create table public.automation_journeys (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  name text not null,
  trigger_event text not null,
  active boolean not null default false,
  steps_json jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.journey_runs (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  journey_id uuid not null references public.automation_journeys(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  current_step integer not null default 0,
  status text not null default 'running' check (status in ('running','completed','failed','cancelled')),
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  last_step_at timestamptz
);
create index journey_runs_journey_idx on public.journey_runs(journey_id, status);

alter table public.automation_journeys enable row level security;
alter table public.journey_runs enable row level security;
do $$
declare t text;
begin
  for t in select unnest(array['automation_journeys','journey_runs']) loop
    execute format('create policy "%I_rw" on public.%I for all to authenticated using (boutique_id = (current_setting(''app.boutique_id'', true))::uuid) with check (boutique_id = (current_setting(''app.boutique_id'', true))::uuid)', t, t);
    execute format('create policy "%I_service" on public.%I for all to service_role using (true) with check (true)', t, t);
  end loop;
end $$;
