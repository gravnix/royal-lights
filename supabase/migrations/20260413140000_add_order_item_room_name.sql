-- Free-text room label per line (optional; room_id may still exist on legacy rows).
ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS room_name text;

COMMENT ON COLUMN public.order_items.room_name IS 'Room / location label (free text).';

-- Optional: copy catalog room names into text for existing FK rows so the UI shows text immediately.
UPDATE public.order_items oi
SET room_name = r.name
FROM public.rooms r
WHERE oi.room_id = r.id
  AND (oi.room_name IS NULL OR btrim(oi.room_name) = '');
