-- Quotes and quote_items tables for הצעת מחיר (price quote) feature.

CREATE TABLE IF NOT EXISTS public.quotes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
  quote_number serial,
  status text NOT NULL DEFAULT 'Sent',
  notes text,
  total_price numeric(12,2) NOT NULL DEFAULT 0,
  vat_enabled boolean NOT NULL DEFAULT true,
  pdf_url text,
  converted_order_id uuid REFERENCES public.orders(id),
  created_by text,
  updated_by text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.quote_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_id uuid NOT NULL REFERENCES public.quotes(id) ON DELETE CASCADE,
  item_number text,
  name text NOT NULL DEFAULT '',
  quantity numeric(10,3) NOT NULL DEFAULT 1,
  extras text,
  price numeric(12,2) NOT NULL DEFAULT 0,
  extras_price numeric(12,2) NOT NULL DEFAULT 0,
  notes text,
  created_at timestamptz DEFAULT now()
);

-- RLS
ALTER TABLE public.quotes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users full access" ON public.quotes;
CREATE POLICY "Authenticated users full access"
  ON public.quotes
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

ALTER TABLE public.quote_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users full access" ON public.quote_items;
CREATE POLICY "Authenticated users full access"
  ON public.quote_items
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);
