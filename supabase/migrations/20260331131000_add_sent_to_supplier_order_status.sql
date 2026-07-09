DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'order_status'
      AND e.enumlabel = 'Sent to Supplier'
  ) THEN
    ALTER TYPE order_status ADD VALUE 'Sent to Supplier';
  END IF;
END $$;

