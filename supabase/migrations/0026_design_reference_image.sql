-- 0026: reference-photo seed for designs + private storage bucket
-- Applied to cloud project tdnwdlrkbrtoxjzcgusg via Supabase MCP (2026-05-31).
-- Lets a Design be seeded by a reference photo (Pinterest/Instagram/camera roll)
-- in addition to / instead of a hand-drawn sketch.

alter table public.designs
  add column if not exists reference_image_path text;

-- Private bucket, staff-only — mirrors design-sketches access rules from 0019.
insert into storage.buckets (id, name, public)
values ('design-references', 'design-references', false)
on conflict (id) do nothing;

do $$ begin
  create policy "design-references staff read"
    on storage.objects for select
    using (bucket_id = 'design-references' and auth.role() = 'authenticated');
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "design-references staff write"
    on storage.objects for insert
    with check (bucket_id = 'design-references' and auth.role() = 'authenticated');
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "design-references staff delete"
    on storage.objects for delete
    using (bucket_id = 'design-references' and auth.role() = 'authenticated');
exception when duplicate_object then null; end $$;
