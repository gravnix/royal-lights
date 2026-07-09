-- Per line item: 0 = no warranty, 3 = three years, 5 = five years.
ALTER TABLE order_items
  ADD COLUMN IF NOT EXISTS warranty_years INTEGER NOT NULL DEFAULT 0;
