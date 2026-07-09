-- Inventory items (stock catalog)

create table if not exists public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  description text not null,
  image_url text,
  brand text,
  barcode text,
  consumer_price numeric,
  available_stock integer not null default 0,
  is_weighted boolean not null default false,
  is_vat_exempt boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists inventory_items_description_idx
  on public.inventory_items(description);

create index if not exists inventory_items_brand_idx
  on public.inventory_items(brand);

create index if not exists inventory_items_barcode_idx
  on public.inventory_items(barcode);

-- Barcodes should be unique when provided.
create unique index if not exists inventory_items_barcode_unique_idx
  on public.inventory_items(barcode)
  where barcode is not null and barcode <> '';

