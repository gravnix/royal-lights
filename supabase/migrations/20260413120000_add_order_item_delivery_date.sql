-- Per-line delivery / shipping date (order-level date remains as denormalized summary).
ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS delivery_date date;

COMMENT ON COLUMN public.order_items.delivery_date IS 'Planned or actual delivery date for this line.';

-- Backfill from legacy orders.delivery_date when lines had no per-item date.
UPDATE public.order_items oi
SET delivery_date = o.delivery_date
FROM public.orders o
WHERE oi.order_id = o.id
  AND oi.delivery_date IS NULL
  AND o.delivery_date IS NOT NULL;
