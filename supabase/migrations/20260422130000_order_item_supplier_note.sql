-- Supplier line messages use existing order_items.notes (no separate column).
-- Clean up if a previous revision added supplier_note; copy into notes then drop.
ALTER TABLE orders DROP COLUMN IF EXISTS supplier_notes;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'order_items'
      AND column_name = 'supplier_note'
  ) THEN
    UPDATE order_items
    SET notes = supplier_note
    WHERE supplier_note IS NOT NULL
      AND btrim(supplier_note) <> ''
      AND (notes IS NULL OR btrim(COALESCE(notes, '')) = '');
    ALTER TABLE order_items DROP COLUMN supplier_note;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
