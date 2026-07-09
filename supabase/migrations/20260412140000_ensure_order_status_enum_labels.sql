-- App sends human-readable labels (e.g. 'Preparing') matching lib/models/order.dart dbValue.
-- Older databases may lack enum labels → PostgreSQL 22P02 "invalid input value for enum order_status".
-- Idempotent: safe to re-run. Uses pg_enum checks (works where ADD VALUE IF NOT EXISTS is unavailable).

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'order_status' AND e.enumlabel = 'Preparing'
  ) THEN
    ALTER TYPE order_status ADD VALUE 'Preparing';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'order_status' AND e.enumlabel = 'Sent to Supplier'
  ) THEN
    ALTER TYPE order_status ADD VALUE 'Sent to Supplier';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'order_status' AND e.enumlabel = 'In Assembly'
  ) THEN
    ALTER TYPE order_status ADD VALUE 'In Assembly';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'order_status' AND e.enumlabel = 'Awaiting Shipping'
  ) THEN
    ALTER TYPE order_status ADD VALUE 'Awaiting Shipping';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'order_status' AND e.enumlabel = 'Handled'
  ) THEN
    ALTER TYPE order_status ADD VALUE 'Handled';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'order_status' AND e.enumlabel = 'Delivered'
  ) THEN
    ALTER TYPE order_status ADD VALUE 'Delivered';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'order_status' AND e.enumlabel = 'Canceled'
  ) THEN
    ALTER TYPE order_status ADD VALUE 'Canceled';
  END IF;
END $$;
