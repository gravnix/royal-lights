-- Discount (הנחה) on price quotes, mirroring the order form's fields.
--
-- Note the same overload orders use: when discount_type is 'fixed_amount'
-- the discount_percentage column holds shekels, not a percentage.
--
-- Declared numeric(12,2) from the start. Orders shipped this as numeric(5,2)
-- and later needed 20260520120000_widen_order_discount_percentage.sql once
-- fixed-amount discounts stopped fitting; no reason to repeat that here.

ALTER TABLE public.quotes
  ADD COLUMN IF NOT EXISTS discount_percentage numeric(12,2) NOT NULL DEFAULT 0;

ALTER TABLE public.quotes
  ADD COLUMN IF NOT EXISTS discount_type text NOT NULL DEFAULT 'percentage';

COMMENT ON COLUMN public.quotes.discount_percentage IS
  'Discount value. A percentage (0-100) when discount_type is ''percentage'', otherwise an amount in ILS.';
COMMENT ON COLUMN public.quotes.discount_type IS
  'Either ''percentage'' or ''fixed_amount''.';
