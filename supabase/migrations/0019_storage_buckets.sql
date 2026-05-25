-- Plan 1, Task 1.17 — storage bucket policies
-- Buckets themselves are created via scripts/create-buckets.sh (idempotent).

drop policy if exists "product_images_public_read" on storage.objects;
drop policy if exists "product_images_staff_write" on storage.objects;
drop policy if exists "vto_uploads_staff" on storage.objects;
drop policy if exists "vto_results_public_read" on storage.objects;
drop policy if exists "vto_results_staff_write" on storage.objects;
drop policy if exists "design_sketches_staff" on storage.objects;
drop policy if exists "design_renders_staff" on storage.objects;
drop policy if exists "customer_photos_staff" on storage.objects;
drop policy if exists "fabrics_staff" on storage.objects;
drop policy if exists "invoices_staff" on storage.objects;
drop policy if exists "measurements_staff" on storage.objects;

create policy "product_images_public_read" on storage.objects for select to anon
  using (bucket_id = 'product-images');
create policy "product_images_staff_write" on storage.objects for all to authenticated
  using (bucket_id = 'product-images') with check (bucket_id = 'product-images');

create policy "vto_uploads_staff" on storage.objects for all to authenticated
  using (bucket_id = 'vto-uploads') with check (bucket_id = 'vto-uploads');

create policy "vto_results_public_read" on storage.objects for select to anon
  using (bucket_id = 'vto-results');
create policy "vto_results_staff_write" on storage.objects for all to authenticated
  using (bucket_id = 'vto-results') with check (bucket_id = 'vto-results');

create policy "design_sketches_staff" on storage.objects for all to authenticated
  using (bucket_id = 'design-sketches') with check (bucket_id = 'design-sketches');

create policy "design_renders_staff" on storage.objects for all to authenticated
  using (bucket_id = 'design-renders') with check (bucket_id = 'design-renders');

create policy "customer_photos_staff" on storage.objects for all to authenticated
  using (bucket_id = 'customer-photos') with check (bucket_id = 'customer-photos');

create policy "fabrics_staff" on storage.objects for all to authenticated
  using (bucket_id = 'fabrics') with check (bucket_id = 'fabrics');

create policy "invoices_staff" on storage.objects for all to authenticated
  using (bucket_id = 'invoices') with check (bucket_id = 'invoices');

create policy "measurements_staff" on storage.objects for all to authenticated
  using (bucket_id = 'measurements-photos') with check (bucket_id = 'measurements-photos');
