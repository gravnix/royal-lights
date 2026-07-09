-- Storage bucket + policies for inventory item photos
-- Bucket: inventory-item-photos

-- Create bucket (public read). Safe to run multiple times.
insert into storage.buckets (id, name, public)
values ('inventory-item-photos', 'inventory-item-photos', true)
on conflict (id) do update
set public = excluded.public;

-- Public read access to objects in this bucket.
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Public read inventory item photos'
  ) then
    create policy "Public read inventory item photos"
      on storage.objects
      for select
      using (bucket_id = 'inventory-item-photos');
  end if;
end $$;

-- Authenticated users can upload (insert) into this bucket.
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Authenticated upload inventory item photos'
  ) then
    create policy "Authenticated upload inventory item photos"
      on storage.objects
      for insert
      to authenticated
      with check (bucket_id = 'inventory-item-photos');
  end if;
end $$;

-- Authenticated users can update metadata for objects in this bucket.
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Authenticated update inventory item photos'
  ) then
    create policy "Authenticated update inventory item photos"
      on storage.objects
      for update
      to authenticated
      using (bucket_id = 'inventory-item-photos')
      with check (bucket_id = 'inventory-item-photos');
  end if;
end $$;

-- Authenticated users can delete objects in this bucket.
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Authenticated delete inventory item photos'
  ) then
    create policy "Authenticated delete inventory item photos"
      on storage.objects
      for delete
      to authenticated
      using (bucket_id = 'inventory-item-photos');
  end if;
end $$;

