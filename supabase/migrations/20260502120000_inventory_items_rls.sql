-- Enable RLS on inventory_items and grant authenticated users full access,
-- matching the pattern used for the rest of the schema (customers, orders, etc.).
-- Without this, if RLS gets toggled on from the dashboard the app silently sees
-- zero rows because no SELECT policy exists.

alter table public.inventory_items enable row level security;

drop policy if exists "Authenticated users full access" on public.inventory_items;
create policy "Authenticated users full access"
  on public.inventory_items
  for all
  to authenticated
  using (true)
  with check (true);
