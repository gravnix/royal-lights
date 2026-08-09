-- Storage bucket + policies for quote PDF files.

INSERT INTO storage.buckets (id, name, public)
VALUES ('quote-pdfs', 'quote-pdfs', true)
ON CONFLICT (id) DO UPDATE
SET public = excluded.public;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Public read quote pdfs'
  ) then
    create policy "Public read quote pdfs"
      on storage.objects
      for select
      using (bucket_id = 'quote-pdfs');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Authenticated upload quote pdfs'
  ) then
    create policy "Authenticated upload quote pdfs"
      on storage.objects
      for insert
      to authenticated
      with check (bucket_id = 'quote-pdfs');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Authenticated update quote pdfs'
  ) then
    create policy "Authenticated update quote pdfs"
      on storage.objects
      for update
      to authenticated
      using (bucket_id = 'quote-pdfs')
      with check (bucket_id = 'quote-pdfs');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Authenticated delete quote pdfs'
  ) then
    create policy "Authenticated delete quote pdfs"
      on storage.objects
      for delete
      to authenticated
      using (bucket_id = 'quote-pdfs');
  end if;
end $$;
