-- ============================================================
-- Royal Light Tira — Store Management App
-- Supabase SQL Schema Migration
-- ============================================================

-- 1. ENUM TYPES
CREATE TYPE order_status AS ENUM (
  'Active',
  'Preparing',
  'Sent to Supplier',
  'In Assembly',
  'Awaiting Shipping',
  'Handled',
  'Delivered',
  'Canceled'
);
CREATE TYPE payment_type AS ENUM ('Cash', 'Credit', 'Check');

-- 2. PROFILES TABLE (extends auth.users)
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username TEXT NOT NULL UNIQUE,
  full_name TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id, username, full_name)
  VALUES (NEW.id, NEW.raw_user_meta_data->>'username', NEW.raw_user_meta_data->>'full_name');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- 3. CUSTOMERS TABLE
CREATE TABLE IF NOT EXISTS customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  card_name TEXT NOT NULL UNIQUE,
  customer_name TEXT NOT NULL,
  phones TEXT[] DEFAULT '{}',
  location TEXT,
  notes TEXT,
  created_by TEXT,
  updated_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. SUPPLIERS TABLE
CREATE TABLE IF NOT EXISTS suppliers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_name TEXT NOT NULL,
  contact_name TEXT,
  phone TEXT,
  notes TEXT,
  created_by TEXT,
  updated_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5. ROOMS TABLE
CREATE TABLE IF NOT EXISTS rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  created_by TEXT,
  updated_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 6. ORDERS TABLE
CREATE TABLE IF NOT EXISTS orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
  order_number SERIAL,
  assembly_required BOOLEAN NOT NULL DEFAULT FALSE,
  assembly_date DATE,
  delivery_date DATE,
  assembly_price NUMERIC(12,2) NOT NULL DEFAULT 0,
  status order_status NOT NULL DEFAULT 'Active',
  total_price NUMERIC(12,2) NOT NULL DEFAULT 0,
  notes TEXT,
  created_by TEXT,
  updated_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 7. ORDER_ITEMS TABLE (11 columns as specified)
CREATE TABLE IF NOT EXISTS order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  item_number TEXT,            -- 1. Barcode-ready item number
  name TEXT NOT NULL,          -- 2. Item name
  image_url TEXT,              -- 3. Upload/Camera image path
  quantity INTEGER NOT NULL DEFAULT 1, -- 4. Quantity
  extras TEXT,                 -- 5. Extras
  notes TEXT,                  -- 6. Notes (order form: per-line supplier WhatsApp text)
  price NUMERIC(12,2) NOT NULL DEFAULT 0, -- 7. Unit price
  extras_price NUMERIC(12,2) NOT NULL DEFAULT 0, -- Add-ons price (per line)
  assembly_required BOOLEAN NOT NULL DEFAULT FALSE, -- 8. Assembly Required
  room_id UUID REFERENCES rooms(id) ON DELETE SET NULL, -- 9. Room dropdown
  supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL, -- 10. Supplier dropdown
  delivery_date DATE, -- per-line shipping / delivery (optional)
  existing_in_store BOOLEAN NOT NULL DEFAULT TRUE, -- 11. Existing In Store
  ready_for_pickup BOOLEAN NOT NULL DEFAULT FALSE, -- line is ready for pickup (partial readiness)
  inventory_item_id UUID REFERENCES inventory_items(id) ON DELETE SET NULL, -- link to inventory for stock deduction
  inventory_deducted BOOLEAN NOT NULL DEFAULT FALSE, -- stock deducted once order is completed
  warranty_years INTEGER NOT NULL DEFAULT 0, -- 0 = none, 3 or 5 = years
  warranty_start_date DATE, -- when warranty starts counting (usually delivery date)
  created_by TEXT,
  updated_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 8. PAYMENTS TABLE
CREATE TABLE IF NOT EXISTS payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
  order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  type payment_type NOT NULL DEFAULT 'Cash',
  card_name TEXT NOT NULL,
  customer_name TEXT NOT NULL,
  amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  image_url TEXT,              -- Camera receipt
  notes TEXT,
  created_by TEXT,
  updated_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- AUTO-UPDATE updated_at TRIGGER
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to all mutable tables
CREATE TRIGGER set_updated_at BEFORE UPDATE ON customers
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON suppliers
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON rooms
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON order_items
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON payments
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_assembly_date ON orders(assembly_date);
CREATE INDEX idx_order_items_order ON order_items(order_id);
CREATE INDEX idx_order_items_supplier ON order_items(supplier_id);
CREATE INDEX idx_payments_customer ON payments(customer_id);
CREATE INDEX idx_payments_order ON payments(order_id);
CREATE INDEX idx_payments_date ON payments(date);

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users full access (staff-only app)
CREATE POLICY "Authenticated users full access" ON profiles
  FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users full access" ON customers
  FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users full access" ON suppliers
  FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users full access" ON rooms
  FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users full access" ON orders
  FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users full access" ON order_items
  FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users full access" ON payments
  FOR ALL USING (auth.role() = 'authenticated');

-- ============================================================
-- CUSTOMER DEBT VIEW (auto-calculated)
-- ============================================================
CREATE OR REPLACE VIEW customer_debts AS
SELECT
  c.id AS customer_id,
  c.card_name,
  c.customer_name,
  COALESCE(o.total_orders, 0) AS total_orders_amount,
  COALESCE(p.total_payments, 0) AS total_payments_amount,
  COALESCE(o.total_orders, 0) - COALESCE(p.total_payments, 0) AS remaining_debt
FROM customers c
LEFT JOIN (
  SELECT customer_id, SUM(total_price) AS total_orders
  FROM orders WHERE status != 'Canceled'
  GROUP BY customer_id
) o ON c.id = o.customer_id
LEFT JOIN (
  SELECT customer_id, SUM(amount) AS total_payments
  FROM payments
  GROUP BY customer_id
) p ON c.id = p.customer_id;

-- ============================================================
-- SEED DATA: Default rooms
-- ============================================================
INSERT INTO rooms (name) VALUES
  ('סלון'),        -- Living Room
  ('חדר שינה'),    -- Bedroom
  ('מטבח'),        -- Kitchen
  ('חדר אמבטיה'),  -- Bathroom
  ('חדר ילדים'),   -- Kids Room
  ('מרפסת'),       -- Balcony
  ('משרד'),        -- Office
  ('אחר');         -- Other

-- ============================================================
-- STORAGE: payment receipts (Supabase Dashboard → Storage)
-- ============================================================
-- 1. Create bucket: id = payment-receipts, name = payment-receipts, Public = ON
-- 2. Run policies (adjust if your project already defines storage policies):
--
-- CREATE POLICY "payment_receipts_public_read"
--   ON storage.objects FOR SELECT
--   USING (bucket_id = 'payment-receipts');
--
-- CREATE POLICY "payment_receipts_authenticated_insert"
--   ON storage.objects FOR INSERT TO authenticated
--   WITH CHECK (bucket_id = 'payment-receipts');
--
-- CREATE POLICY "payment_receipts_authenticated_update"
--   ON storage.objects FOR UPDATE TO authenticated
--   USING (bucket_id = 'payment-receipts');
--
-- CREATE POLICY "payment_receipts_authenticated_delete"
--   ON storage.objects FOR DELETE TO authenticated
--   USING (bucket_id = 'payment-receipts');

-- ============================================================
-- MIGRATIONS (run once on existing databases)
-- ============================================================
-- ALTER TABLE order_items ADD COLUMN IF NOT EXISTS extras_price NUMERIC(12,2) NOT NULL DEFAULT 0;
