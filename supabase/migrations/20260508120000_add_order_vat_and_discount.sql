-- Per-order VAT toggle and discount percentage.

alter table public.orders
  add column if not exists vat_enabled boolean not null default true;

alter table public.orders
  add column if not exists discount_percentage numeric(5, 2) not null default 0;
