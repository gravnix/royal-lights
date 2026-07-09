-- Fixing / warranty tickets (separate from customer orders)

create table if not exists public.fixing_tickets (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete cascade,
  status text not null default 'Pending', -- Pending | Fixed
  fixed_at timestamptz,
  created_by text,
  updated_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists fixing_tickets_customer_id_idx
  on public.fixing_tickets(customer_id);

create index if not exists fixing_tickets_status_idx
  on public.fixing_tickets(status);

create table if not exists public.fixing_ticket_items (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.fixing_tickets(id) on delete cascade,
  source_order_id uuid references public.orders(id) on delete set null,
  source_order_item_id uuid references public.order_items(id) on delete set null,
  name text not null,
  item_number text,
  quantity integer not null default 1,
  notes text,
  warranty_years integer not null default 0,
  delivery_date date, -- snapshot from the order.delivery_date
  created_by text,
  updated_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists fixing_ticket_items_ticket_id_idx
  on public.fixing_ticket_items(ticket_id);

