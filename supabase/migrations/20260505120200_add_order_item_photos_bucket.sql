-- Storage bucket + policies for manually-uploaded order item photos.
-- Bucket: order-item-photos

insert into storage.buckets (id, name, public)
values ('order-item-photos', 'order-item-photos', true)
on conflict (id) do update
set public = excluded.public;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Public read order item photos'
  ) then
    create policy "Public read order item photos"
      on storage.objects
      for select
      using (bucket_id = 'order-item-photos');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Authenticated upload order item photos'
  ) then
    create policy "Authenticated upload order item photos"
      on storage.objects
      for insert
      to authenticated
      with check (bucket_id = 'order-item-photos');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Authenticated update order item photos'
  ) then
    create policy "Authenticated update order item photos"
      on storage.objects
      for update
      to authenticated
      using (bucket_id = 'order-item-photos')
      with check (bucket_id = 'order-item-photos');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Authenticated delete order item photos'
  ) then
    create policy "Authenticated delete order item photos"
      on storage.objects
      for delete
      to authenticated
      using (bucket_id = 'order-item-photos');
  end if;
end $$;
