-- Start warranty counting from delivery date (once it begins) or when delivered.

-- Ensure orders has delivery_date (older DBs may miss it).
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS delivery_date DATE;

ALTER TABLE order_items
ADD COLUMN IF NOT EXISTS warranty_start_date DATE;

-- Backfill: if order is delivered OR delivery date already began, start from delivery_date.
UPDATE order_items oi
SET warranty_start_date = o.delivery_date
FROM orders o
WHERE oi.order_id = o.id
  AND oi.warranty_years > 0
  AND oi.warranty_start_date IS NULL
  AND o.delivery_date IS NOT NULL
  AND ((o.status::text = 'Delivered') OR o.delivery_date <= CURRENT_DATE);

-- Trigger: when an order becomes Delivered, start warranties (if not started).
CREATE OR REPLACE FUNCTION start_warranty_on_order_delivered()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status::text = 'Delivered' AND (OLD.status IS DISTINCT FROM NEW.status) THEN
    UPDATE order_items
    SET warranty_start_date = COALESCE(NEW.delivery_date, CURRENT_DATE)
    WHERE order_id = NEW.id
      AND warranty_years > 0
      AND warranty_start_date IS NULL;
  END IF;

  -- If delivery_date is set/changed and is today or earlier, start warranties.
  IF NEW.delivery_date IS NOT NULL
     AND (OLD.delivery_date IS DISTINCT FROM NEW.delivery_date)
     AND NEW.delivery_date <= CURRENT_DATE THEN
    UPDATE order_items
    SET warranty_start_date = NEW.delivery_date
    WHERE order_id = NEW.id
      AND warranty_years > 0
      AND warranty_start_date IS NULL;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_start_warranty_on_order_delivered ON orders;
CREATE TRIGGER trg_start_warranty_on_order_delivered
AFTER UPDATE OF status, delivery_date ON orders
FOR EACH ROW
EXECUTE FUNCTION start_warranty_on_order_delivered();

