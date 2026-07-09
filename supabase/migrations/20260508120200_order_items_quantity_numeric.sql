-- Allow fractional quantities on order_items (e.g. 1.5 m of cable, 0.75 kg).
-- Inventory stock remains integer; the deduction function rounds up so we
-- never under-deduct when a partial unit is consumed.

alter table public.order_items
  alter column quantity type numeric(10, 3) using quantity::numeric(10, 3);

alter table public.order_items
  alter column quantity set default 1;

create or replace function public.deduct_inventory_for_order(
  p_order_id uuid,
  p_username text
)
returns void
language plpgsql
as $$
begin
  with lines as (
    select
      oi.id as order_item_id,
      oi.inventory_item_id,
      oi.quantity
    from public.order_items oi
    where oi.order_id = p_order_id
      and oi.inventory_item_id is not null
      and oi.inventory_deducted = false
  ),
  updated_inventory as (
    update public.inventory_items ii
    set
      available_stock = greatest(0, ii.available_stock - ceil(l.quantity)::int),
      updated_at = now()
    from lines l
    where ii.id = l.inventory_item_id
    returning ii.id
  )
  update public.order_items oi
  set
    inventory_deducted = true,
    updated_by = p_username,
    updated_at = now()
  from lines l
  where oi.id = l.order_item_id;
end;
$$;
