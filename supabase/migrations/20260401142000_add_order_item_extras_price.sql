-- Ensure add-ons price column exists for order items.
-- Some older DBs were created before this column was added.
ALTER TABLE order_items
  ADD COLUMN IF NOT EXISTS extras_price NUMERIC(12,2) NOT NULL DEFAULT 0;

