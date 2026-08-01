-- BACKFILLED 2026-07-31 from supabase_migrations.schema_migrations.
-- Applied to production 2026-05-26 (version 20260526114135).
-- RECORD of SQL that has already run — do not re-apply as a new migration.
--
-- Creates the job_cards table the karigar workflow is built on. Later
-- migrations add share_token + job_card_events (R4d) on top of this.
-- Note `measurements_json` and `fabric_list_json`: these are the jsonb columns
-- whose contents reach the karigar's public HTML page, which is why
-- job-card-view/index.ts must escape them (fixed 2026-07-31).

do $$ begin
  create type public.job_card_status as enum ('draft','issued','in_progress','ready','delivered','cancelled');
exception when duplicate_object then null;
end $$;

create table if not exists public.job_cards (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  job_number text not null,
  design_id uuid references public.designs(id) on delete set null,
  order_id uuid references public.orders(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,
  garment_type text,
  occasion text,
  assigned_karigar_id uuid references public.staff_users(id) on delete set null,
  due_date date,
  status public.job_card_status not null default 'draft',

  -- Snapshot data — captured at issue time so karigar's brief never changes
  measurements_json jsonb,
  fabric_list_json jsonb default '[]'::jsonb,     -- [{name, color, quantity_m, supplier, role}]
  embellishments text,
  special_instructions text,
  hindi_brief text,                                 -- AI-generated Romanized Hindi tailor brief
  sketch_image_path text,                           -- canonical path; signed URL generated on read
  render_image_path text,

  -- Stages tracking (per-boutique config in settings; we store current_stage_index + completed[])
  current_stage integer not null default 0,
  stages_progress_json jsonb default '[]'::jsonb,   -- [{stage_name, completed_at, notes}]

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists job_cards_number_unique on public.job_cards(boutique_id, job_number);
create index if not exists job_cards_design_idx on public.job_cards(design_id);
create index if not exists job_cards_order_idx on public.job_cards(order_id);
create index if not exists job_cards_karigar_idx on public.job_cards(assigned_karigar_id);
create index if not exists job_cards_status_idx on public.job_cards(boutique_id, status);

alter table public.job_cards enable row level security;
drop policy if exists "job_cards_rw" on public.job_cards;
create policy "job_cards_rw" on public.job_cards for all to authenticated
  using (boutique_id = public.current_boutique_id())
  with check (boutique_id = public.current_boutique_id());
drop policy if exists "job_cards_service" on public.job_cards;
create policy "job_cards_service" on public.job_cards for all to service_role using (true) with check (true);

drop trigger if exists job_cards_updated_at on public.job_cards;
create trigger job_cards_updated_at before update on public.job_cards
  for each row execute function public.set_updated_at();

-- Add 'karigar' role to staff_users enum if not present
do $$
begin
  alter type public.staff_role add value if not exists 'karigar';
exception when others then null;
end $$;

-- Seed default workshop stages in settings (per-boutique configurable)
insert into public.settings (boutique_id, key, value_json, is_secret)
values (
  '00000000-0000-0000-0000-000000000001',
  'workshop_stages',
  '["Cutting","Stitching","Embroidery","Trial fitting","Finishing","QC","Ready"]'::jsonb,
  false
)
on conflict (boutique_id, key) do nothing;
