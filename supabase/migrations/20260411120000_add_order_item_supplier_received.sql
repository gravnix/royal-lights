-- Track which line items have arrived from the supplier (order fulfillment workflow).
ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS supplier_received boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.order_items.supplier_received IS 'True once this line is confirmed received from supplier (partial fulfillment supported).';

-- Lines already marked as in-store do not wait on a supplier shipment.
UPDATE public.order_items
SET supplier_received = true
WHERE existing_in_store = true;
