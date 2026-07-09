ALTER TABLE orders ADD COLUMN IF NOT EXISTS discount_type TEXT NOT NULL DEFAULT 'percentage';
-- discount_type can be 'percentage' or 'fixed_amount'
