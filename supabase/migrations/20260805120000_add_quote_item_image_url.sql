-- Add image_url to quote_items so product photos can appear on quote PDFs.

ALTER TABLE public.quote_items
  ADD COLUMN IF NOT EXISTS image_url text;
