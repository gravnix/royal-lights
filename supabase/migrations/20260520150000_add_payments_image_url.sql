-- Ensure payments can store receipt / check photo references
ALTER TABLE payments ADD COLUMN IF NOT EXISTS image_url text;
