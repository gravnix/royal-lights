-- Track which line items are ready for pickup (partial readiness supported).
ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS ready_for_pickup boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.order_items.ready_for_pickup IS 'True once this line is confirmed ready for customer pickup (partial readiness supported).';

