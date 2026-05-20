-- Allow fixed-amount discounts (stored in discount_percentage when type = fixed_amount).
alter table public.orders
  alter column discount_percentage type numeric(12, 2);
