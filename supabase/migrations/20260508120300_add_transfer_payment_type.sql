-- Add 'Transfer' (העברה) to the payment_type enum.
-- Idempotent: this is a no-op if the value already exists (e.g. from a
-- prior application that was rolled back at the code level only).

alter type payment_type add value if not exists 'Transfer';
