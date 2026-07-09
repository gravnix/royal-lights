-- Auto-restock settings per inventory item + generated restock orders

alter table public.inventory_items
  add column if not exists auto_restock_enabled boolean not null default false,
  add column if not exists auto_restock_threshold integer not null default 0,
  add column if not exists auto_restock_quantity integer not null default 1;

-- Restock orders (grouped by supplier)
create table if not exists public.restock_orders (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  status text not null default 'Open',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists restock_orders_supplier_status_idx
  on public.restock_orders(supplier_id, status);

create table if not exists public.restock_order_items (
  id uuid primary key default gen_random_uuid(),
  restock_order_id uuid not null references public.restock_orders(id) on delete cascade,
  inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
  quantity integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(restock_order_id, inventory_item_id)
);

create index if not exists restock_order_items_order_idx
  on public.restock_order_items(restock_order_id);

create index if not exists restock_order_items_inventory_item_idx
  on public.restock_order_items(inventory_item_id);

-- updated_at triggers
drop trigger if exists set_updated_at_restock_orders on public.restock_orders;
create trigger set_updated_at_restock_orders
  before update on public.restock_orders
  for each row execute function public.update_updated_at();

drop trigger if exists set_updated_at_restock_order_items on public.restock_order_items;
create trigger set_updated_at_restock_order_items
  before update on public.restock_order_items
  for each row execute function public.update_updated_at();

-- RLS
alter table public.restock_orders enable row level security;
alter table public.restock_order_items enable row level security;

drop policy if exists "Authenticated users full access" on public.restock_orders;
create policy "Authenticated users full access" on public.restock_orders
  for all using (auth.role() = 'authenticated');

drop policy if exists "Authenticated users full access" on public.restock_order_items;
create policy "Authenticated users full access" on public.restock_order_items
  for all using (auth.role() = 'authenticated');

-- Creates/updates an "Open" restock order line for an item when stock drops below threshold.
create or replace function public.maybe_create_restock_for_inventory_item(p_item_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_item record;
  v_order_id uuid;
begin
  select
    id,
    supplier_id,
    available_stock,
    auto_restock_enabled,
    auto_restock_threshold,
    auto_restock_quantity
  into v_item
  from public.inventory_items
  where id = p_item_id;

  if v_item is null then
    return;
  end if;

  if v_item.auto_restock_enabled is not true then
    return;
  end if;

  -- Threshold <= 0 means "disabled" even if enabled flag is on.
  if coalesce(v_item.auto_restock_threshold, 0) <= 0 then
    return;
  end if;

  if v_item.supplier_id is null then
    return;
  end if;

  if coalesce(v_item.available_stock, 0) >= v_item.auto_restock_threshold then
    return;
  end if;

  -- Find an existing open order for the supplier (or create a new one).
  select id
    into v_order_id
  from public.restock_orders
  where supplier_id = v_item.supplier_id
    and status = 'Open'
  order by created_at desc
  limit 1;

  if v_order_id is null then
    insert into public.restock_orders (supplier_id, status)
    values (v_item.supplier_id, 'Open')
    returning id into v_order_id;
  end if;

  -- Upsert the line (don’t create duplicates on repeated updates while low).
  insert into public.restock_order_items (
    restock_order_id,
    inventory_item_id,
    quantity
  )
  values (
    v_order_id,
    v_item.id,
    greatest(coalesce(v_item.auto_restock_quantity, 1), 1)
  )
  on conflict (restock_order_id, inventory_item_id)
  do update set quantity = greatest(excluded.quantity, restock_order_items.quantity);
end;
$$;

drop trigger if exists inventory_items_auto_restock_trigger on public.inventory_items;

-- Trigger wrapper (trigger functions cannot be called with NEW.* args directly).
create or replace function public.inventory_items_auto_restock_trigger_fn()
returns trigger
language plpgsql
security definer
as $$
begin
  perform public.maybe_create_restock_for_inventory_item(new.id);
  return new;
end;
$$;

create trigger inventory_items_auto_restock_trigger
  after update of available_stock on public.inventory_items
  for each row
  when (
    new.auto_restock_enabled is true
    and new.auto_restock_threshold > 0
    and new.supplier_id is not null
    and new.available_stock < new.auto_restock_threshold
  )
  execute function public.inventory_items_auto_restock_trigger_fn();

