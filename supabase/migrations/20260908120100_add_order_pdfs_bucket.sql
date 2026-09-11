-- Storage bucket + policies for order PDF files.

INSERT INTO storage.buckets (id, name, public)
VALUES ('order-pdfs', 'order-pdfs', true)
ON CONFLICT (id) DO UPDATE
SET public = excluded.public;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Public read order pdfs'
  ) then
    create policy "Public read order pdfs"
      on storage.objects
      for select
      using (bucket_id = 'order-pdfs');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Authenticated upload order pdfs'
  ) then
    create policy "Authenticated upload order pdfs"
      on storage.objects
      for insert
      to authenticated
      with check (bucket_id = 'order-pdfs');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Authenticated update order pdfs'
  ) then
    create policy "Authenticated update order pdfs"
      on storage.objects
      for update
      to authenticated
      using (bucket_id = 'order-pdfs')
      with check (bucket_id = 'order-pdfs');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Authenticated delete order pdfs'
  ) then
    create policy "Authenticated delete order pdfs"
      on storage.objects
      for delete
      to authenticated
      using (bucket_id = 'order-pdfs');
  end if;
end $$;
