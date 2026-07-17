-- ═══════════════════════════════════════════════════════════════════════════════
-- THE LEDGER — Bootstrap / Reset (DESTRUCTIVE)
-- Use this ONLY for first-time setup or intentional full reset.
-- This file DROPS app tables and recreates schema from scratch.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── CLEAN SLATE (destructive) ────────────────────────────────────────────────
DROP TRIGGER  IF EXISTS trg_new_user_settings         ON auth.users;
DROP TRIGGER  IF EXISTS trg_user_settings_updated_at  ON user_settings;
DROP FUNCTION IF EXISTS ensure_user_settings_row();
DROP FUNCTION IF EXISTS touch_updated_at();
DROP TABLE    IF EXISTS transactions  CASCADE;
DROP TABLE    IF EXISTS tax_items     CASCADE;
DROP TABLE    IF EXISTS user_settings CASCADE;

-- ─── 1. TRANSACTIONS ──────────────────────────────────────────────────────────
CREATE TABLE transactions (
  id          TEXT            NOT NULL,
  user_id     UUID            NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date        TEXT            NOT NULL,
  description TEXT            NOT NULL DEFAULT '',
  amount      NUMERIC(12, 2)  NOT NULL DEFAULT 0 CHECK (amount >= 0),
  type        TEXT            NOT NULL DEFAULT 'expense'
                              CHECK (type IN ('expense', 'income')),
  category    TEXT            NOT NULL DEFAULT 'other',
  source      TEXT            NOT NULL DEFAULT 'manual'
                              CHECK (source IN ('manual', 'csv')),
  split_group_id TEXT,
  vendor_split_vendor_key TEXT,
  created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, user_id)
);

CREATE INDEX idx_tx_user_date
  ON transactions (user_id, date DESC);
CREATE INDEX idx_tx_user_type_date
  ON transactions (user_id, type, date DESC);
CREATE INDEX idx_tx_user_category_date
  ON transactions (user_id, category, date DESC);

ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tx_select" ON transactions FOR SELECT
  USING (auth.uid() = user_id);
CREATE POLICY "tx_insert" ON transactions FOR INSERT
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "tx_update" ON transactions FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "tx_delete" ON transactions FOR DELETE
  USING (auth.uid() = user_id);

-- ─── 2. TAX ITEMS ─────────────────────────────────────────────────────────────
CREATE TABLE tax_items (
  id          TEXT        NOT NULL,
  user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  grp         TEXT        NOT NULL DEFAULT 'Other',
  title       TEXT        NOT NULL,
  description TEXT        NOT NULL DEFAULT '',
  status      TEXT        NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending', 'ready', 'na')),
  notes       TEXT        NOT NULL DEFAULT '',
  source      TEXT        NOT NULL DEFAULT 'Records',
  custom      BOOLEAN     NOT NULL DEFAULT FALSE,
  sort_order  INTEGER     NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, user_id)
);

CREATE INDEX idx_tax_user_order
  ON tax_items (user_id, sort_order);

ALTER TABLE tax_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tax_select" ON tax_items FOR SELECT
  USING (auth.uid() = user_id);
CREATE POLICY "tax_insert" ON tax_items FOR INSERT
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "tax_update" ON tax_items FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "tax_delete" ON tax_items FOR DELETE
  USING (auth.uid() = user_id);

-- ─── 3. USER SETTINGS ─────────────────────────────────────────────────────────
CREATE TABLE user_settings (
  user_id               UUID            PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  income                NUMERIC(12, 2)  NOT NULL DEFAULT 9664 CHECK (income >= 0),
  budgets               JSONB           NOT NULL DEFAULT '{}',
  keywords              JSONB           NOT NULL DEFAULT '{}',
  envelope_category_ids JSONB           NOT NULL DEFAULT '[]',
  envelope_entries      JSONB           NOT NULL DEFAULT '[]',
  sub_budgets           JSONB           NOT NULL DEFAULT '{}',
  kids_data             JSONB           NOT NULL DEFAULT '[]',
  updated_at            TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

ALTER TABLE user_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "settings_select" ON user_settings FOR SELECT
  USING (auth.uid() = user_id);
CREATE POLICY "settings_insert" ON user_settings FOR INSERT
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "settings_update" ON user_settings FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "settings_delete" ON user_settings FOR DELETE
  USING (auth.uid() = user_id);

-- ─── 4. FUNCTIONS + TRIGGERS ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_user_settings_updated_at
  BEFORE UPDATE ON user_settings
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE OR REPLACE FUNCTION ensure_user_settings_row()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.user_settings (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_new_user_settings
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION ensure_user_settings_row();
