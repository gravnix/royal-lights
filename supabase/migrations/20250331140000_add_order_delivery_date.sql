-- Optional planned / actual delivery date for an order.
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_date DATE;
