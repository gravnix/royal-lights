-- Installation / assembly fee entered on the order (admin).
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS assembly_price NUMERIC(12, 2) NOT NULL DEFAULT 0;
