-- Add warranty choices to inventory items (0/3/5 years)

alter table public.inventory_items
  add column if not exists warranty_years integer not null default 0;

create index if not exists inventory_items_warranty_years_idx
  on public.inventory_items(warranty_years);

