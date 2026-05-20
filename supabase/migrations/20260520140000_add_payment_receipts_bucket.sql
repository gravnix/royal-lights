-- Optional dedicated bucket for payment receipt / check photos.
-- The app uploads to inventory-item-photos/payments/{id}/receipt.jpg by default
-- (see inventory_item_photos migration). Run this only if you prefer a separate bucket.
-- Bucket: payment-receipts

insert into storage.buckets (id, name, public)
values ('payment-receipts', 'payment-receipts', true)
on conflict (id) do update
set public = excluded.public;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Public read payment receipts'
  ) then
    create policy "Public read payment receipts"
      on storage.objects
      for select
      using (bucket_id = 'payment-receipts');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Authenticated upload payment receipts'
  ) then
    create policy "Authenticated upload payment receipts"
      on storage.objects
      for insert
      to authenticated
      with check (bucket_id = 'payment-receipts');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Authenticated update payment receipts'
  ) then
    create policy "Authenticated update payment receipts"
      on storage.objects
      for update
      to authenticated
      using (bucket_id = 'payment-receipts')
      with check (bucket_id = 'payment-receipts');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Authenticated delete payment receipts'
  ) then
    create policy "Authenticated delete payment receipts"
      on storage.objects
      for delete
      to authenticated
      using (bucket_id = 'payment-receipts');
  end if;
end $$;
