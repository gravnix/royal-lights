-- Add 'Transfer' (העברה) to the payment_type enum.

alter type payment_type add value if not exists 'Transfer';
