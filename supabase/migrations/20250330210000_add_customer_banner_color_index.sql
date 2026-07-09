-- Solid header color for customer profile (index 0..9 into app palette).
ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS banner_color_index INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN customers.banner_color_index IS '0-9 index into app customer profile banner palette';
