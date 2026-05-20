-- Delete test Check payments (2026-05-20).
-- If the full script fails, run ONLY the DELETE block below in SQL Editor.
-- (Storage cleanup often fails in SQL Editor — use the app delete button instead.)

-- Preview
SELECT id, date, type::text AS type, card_name, customer_name, amount, notes, created_by
FROM payments
WHERE type = 'Check'::payment_type
  AND date = DATE '2026-05-20'
ORDER BY created_at DESC;

-- >>> Run this block alone if storage step errors <<<
DELETE FROM payments
WHERE type = 'Check'::payment_type
  AND date = DATE '2026-05-20';

-- Verify
SELECT count(*) AS remaining_test_checks
FROM payments
WHERE type = 'Check'::payment_type
  AND date = DATE '2026-05-20';

-- Optional: remove orphan receipt files (may require service role / Dashboard Storage UI)
-- DELETE FROM storage.objects
-- WHERE bucket_id = 'inventory-item-photos'
--   AND name LIKE 'payments/%/receipt.jpg';
