-- Link order items to inventory rows (when picked from inventory)
-- and deduct stock exactly once when an order is completed (Delivered).

ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS inventory_item_id uuid REFERENCES public.inventory_items(id) ON DELETE SET NULL;

ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS inventory_deducted boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.order_items.inventory_item_id IS 'When an order line was created from an inventory item, this links to inventory_items.id for stock deduction.';
COMMENT ON COLUMN public.order_items.inventory_deducted IS 'True once this line has been used to deduct inventory stock after order completion (idempotency).';

CREATE OR REPLACE FUNCTION public.deduct_inventory_for_order(
  p_order_id uuid,
  p_username text
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- Pick only lines that are linked to inventory and not yet deducted.
  WITH lines AS (
    SELECT
      oi.id AS order_item_id,
      oi.inventory_item_id,
      oi.quantity
    FROM public.order_items oi
    WHERE oi.order_id = p_order_id
      AND oi.inventory_item_id IS NOT NULL
      AND oi.inventory_deducted = false
  ),
  updated_inventory AS (
    UPDATE public.inventory_items ii
    SET
      available_stock = GREATEST(0, ii.available_stock - l.quantity),
      updated_at = NOW()
    FROM lines l
    WHERE ii.id = l.inventory_item_id
    RETURNING ii.id
  )
  UPDATE public.order_items oi
  SET
    inventory_deducted = true,
    updated_by = p_username,
    updated_at = NOW()
  FROM lines l
  WHERE oi.id = l.order_item_id;
END;
$$;

