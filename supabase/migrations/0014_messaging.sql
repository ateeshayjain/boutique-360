-- Plan 1, Task 1.15 — message_templates, conversations, messages
create table public.message_templates (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  name text not null,
  channel text not null check (channel in ('whatsapp','email','sms')),
  whatsapp_template_name text,
  whatsapp_template_status text check (whatsapp_template_status in ('draft','submitted','approved','rejected')),
  body_template text not null,
  variables_json jsonb default '[]'::jsonb,
  category text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  channel text not null,
  last_message_at timestamptz,
  unread_count integer default 0,
  assigned_to uuid references public.staff_users(id),
  created_at timestamptz not null default now()
);
create unique index conversations_customer_channel on public.conversations(customer_id, channel);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  direction text not null check (direction in ('out','in')),
  channel text not null,
  template_id uuid references public.message_templates(id),
  body text,
  media_urls text[] default '{}',
  status text not null default 'queued' check (status in ('queued','sent','delivered','read','failed')),
  provider_message_id text,
  error_msg text,
  sent_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index messages_provider_unique on public.messages(provider_message_id) where provider_message_id is not null;
create index messages_conversation_idx on public.messages(conversation_id, created_at desc);

alter table public.message_templates enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;

do $$
declare t text;
begin
  for t in select unnest(array['message_templates','conversations','messages']) loop
    execute format('create policy "%I_rw" on public.%I for all to authenticated using (boutique_id = (current_setting(''app.boutique_id'', true))::uuid) with check (boutique_id = (current_setting(''app.boutique_id'', true))::uuid)', t, t);
    execute format('create policy "%I_service" on public.%I for all to service_role using (true) with check (true)', t, t);
  end loop;
end $$;
