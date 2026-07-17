-- ═══════════════════════════════════════════════════════════════════════════════
-- THE LEDGER — Safe Migrations (NON-DESTRUCTIVE)
-- Use this for normal schema updates. No table drops, no data wipes.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── 1. TABLES / COLUMNS ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS transactions (
  id          TEXT            NOT NULL,
  user_id     UUID            NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date        TEXT            NOT NULL,
  description TEXT            NOT NULL DEFAULT '',
  amount      NUMERIC(12, 2)  NOT NULL DEFAULT 0,
  type        TEXT            NOT NULL DEFAULT 'expense',
  category    TEXT            NOT NULL DEFAULT 'other',
  source      TEXT            NOT NULL DEFAULT 'manual',
  created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, user_id)
);

ALTER TABLE transactions ADD COLUMN IF NOT EXISTS id          TEXT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS user_id     UUID;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS date        TEXT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS description TEXT            NOT NULL DEFAULT '';
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS amount      NUMERIC(12, 2)  NOT NULL DEFAULT 0;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS type        TEXT            NOT NULL DEFAULT 'expense';
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS category    TEXT            NOT NULL DEFAULT 'other';
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS source      TEXT            NOT NULL DEFAULT 'manual';
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW();
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS split_group_id  TEXT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS vendor_split_vendor_key TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'transactions_amount_check'
  ) THEN
    ALTER TABLE transactions ADD CONSTRAINT transactions_amount_check CHECK (amount >= 0);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'transactions_type_check'
  ) THEN
    ALTER TABLE transactions ADD CONSTRAINT transactions_type_check CHECK (type IN ('expense', 'income'));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'transactions_source_check'
  ) THEN
    ALTER TABLE transactions ADD CONSTRAINT transactions_source_check CHECK (source IN ('manual', 'csv'));
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS envelope_entries (
  id          TEXT            NOT NULL,
  user_id     UUID            NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date        TEXT            NOT NULL,
  category    TEXT            NOT NULL DEFAULT 'other',
  description TEXT            NOT NULL DEFAULT '',
  amount      NUMERIC(12, 2)  NOT NULL DEFAULT 0 CHECK (amount >= 0),
  type        TEXT            NOT NULL DEFAULT 'expense'
                              CHECK (type IN ('expense', 'income')),
  source      TEXT            NOT NULL DEFAULT 'envelope',
  created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_envelope_user_date
  ON envelope_entries (user_id, date DESC);

ALTER TABLE envelope_entries ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='envelope_entries' AND policyname='envelope_select'
  ) THEN
    CREATE POLICY "envelope_select" ON envelope_entries FOR SELECT USING (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='envelope_entries' AND policyname='envelope_insert'
  ) THEN
    CREATE POLICY "envelope_insert" ON envelope_entries FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='envelope_entries' AND policyname='envelope_update'
  ) THEN
    CREATE POLICY "envelope_update" ON envelope_entries FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='envelope_entries' AND policyname='envelope_delete'
  ) THEN
    CREATE POLICY "envelope_delete" ON envelope_entries FOR DELETE USING (auth.uid() = user_id);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS tax_items (
  id          TEXT        NOT NULL,
  user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  grp         TEXT        NOT NULL DEFAULT 'Other',
  title       TEXT        NOT NULL,
  description TEXT        NOT NULL DEFAULT '',
  status      TEXT        NOT NULL DEFAULT 'pending',
  notes       TEXT        NOT NULL DEFAULT '',
  source      TEXT        NOT NULL DEFAULT 'Records',
  custom      BOOLEAN     NOT NULL DEFAULT FALSE,
  sort_order  INTEGER     NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, user_id)
);

ALTER TABLE tax_items ADD COLUMN IF NOT EXISTS id          TEXT;
ALTER TABLE tax_items ADD COLUMN IF NOT EXISTS user_id     UUID;
ALTER TABLE tax_items ADD COLUMN IF NOT EXISTS grp         TEXT        NOT NULL DEFAULT 'Other';
ALTER TABLE tax_items ADD COLUMN IF NOT EXISTS title       TEXT        NOT NULL;
ALTER TABLE tax_items ADD COLUMN IF NOT EXISTS description TEXT        NOT NULL DEFAULT '';
ALTER TABLE tax_items ADD COLUMN IF NOT EXISTS status      TEXT        NOT NULL DEFAULT 'pending';
ALTER TABLE tax_items ADD COLUMN IF NOT EXISTS notes       TEXT        NOT NULL DEFAULT '';
ALTER TABLE tax_items ADD COLUMN IF NOT EXISTS source      TEXT        NOT NULL DEFAULT 'Records';
ALTER TABLE tax_items ADD COLUMN IF NOT EXISTS custom      BOOLEAN     NOT NULL DEFAULT FALSE;
ALTER TABLE tax_items ADD COLUMN IF NOT EXISTS sort_order  INTEGER     NOT NULL DEFAULT 0;
ALTER TABLE tax_items ADD COLUMN IF NOT EXISTS created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW();

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'tax_items_status_check'
  ) THEN
    ALTER TABLE tax_items ADD CONSTRAINT tax_items_status_check CHECK (status IN ('pending', 'ready', 'na'));
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS user_settings (
  user_id               UUID            PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  income                NUMERIC(12, 2)  NOT NULL DEFAULT 9664,
  budgets               JSONB           NOT NULL DEFAULT '{}',
  keywords              JSONB           NOT NULL DEFAULT '{}',
  manual_review_keywords JSONB          NOT NULL DEFAULT '[]',
  envelope_category_ids JSONB           NOT NULL DEFAULT '[]',
  envelope_entries      JSONB           NOT NULL DEFAULT '[]',
  sub_budgets           JSONB           NOT NULL DEFAULT '{}',
  kids_data             JSONB           NOT NULL DEFAULT '[]',
  updated_at            TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS user_id               UUID;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS income                NUMERIC(12, 2)  NOT NULL DEFAULT 9664;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS budgets               JSONB           NOT NULL DEFAULT '{}';
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS keywords              JSONB           NOT NULL DEFAULT '{}';
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS manual_review_keywords JSONB          NOT NULL DEFAULT '[]';
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS envelope_category_ids JSONB           NOT NULL DEFAULT '[]';
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS envelope_entries      JSONB           NOT NULL DEFAULT '[]';
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS sub_budgets           JSONB           NOT NULL DEFAULT '{}';
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS kids_data             JSONB           NOT NULL DEFAULT '[]';
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS updated_at            TIMESTAMPTZ     NOT NULL DEFAULT NOW();
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS vendor_matrix         JSONB           NOT NULL DEFAULT '{}';
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS travel_days           JSONB           NOT NULL DEFAULT '[]';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'user_settings_income_check'
  ) THEN
    ALTER TABLE user_settings ADD CONSTRAINT user_settings_income_check CHECK (income >= 0);
  END IF;
END $$;

-- ─── 2. INDEXES ───────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_tx_user_date
  ON transactions (user_id, date DESC);
CREATE INDEX IF NOT EXISTS idx_tx_user_type_date
  ON transactions (user_id, type, date DESC);
CREATE INDEX IF NOT EXISTS idx_tx_user_category_date
  ON transactions (user_id, category, date DESC);
CREATE INDEX IF NOT EXISTS idx_tax_user_order
  ON tax_items (user_id, sort_order);

-- ─── 3. RLS + POLICIES ────────────────────────────────────────────────────────
ALTER TABLE transactions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE tax_items     ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_settings ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='transactions' AND policyname='tx_select'
  ) THEN
    CREATE POLICY "tx_select" ON transactions FOR SELECT USING (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='transactions' AND policyname='tx_insert'
  ) THEN
    CREATE POLICY "tx_insert" ON transactions FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='transactions' AND policyname='tx_update'
  ) THEN
    CREATE POLICY "tx_update" ON transactions FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='transactions' AND policyname='tx_delete'
  ) THEN
    CREATE POLICY "tx_delete" ON transactions FOR DELETE USING (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='tax_items' AND policyname='tax_select'
  ) THEN
    CREATE POLICY "tax_select" ON tax_items FOR SELECT USING (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='tax_items' AND policyname='tax_insert'
  ) THEN
    CREATE POLICY "tax_insert" ON tax_items FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='tax_items' AND policyname='tax_update'
  ) THEN
    CREATE POLICY "tax_update" ON tax_items FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='tax_items' AND policyname='tax_delete'
  ) THEN
    CREATE POLICY "tax_delete" ON tax_items FOR DELETE USING (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_settings' AND policyname='settings_select'
  ) THEN
    CREATE POLICY "settings_select" ON user_settings FOR SELECT USING (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_settings' AND policyname='settings_insert'
  ) THEN
    CREATE POLICY "settings_insert" ON user_settings FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_settings' AND policyname='settings_update'
  ) THEN
    CREATE POLICY "settings_update" ON user_settings FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_settings' AND policyname='settings_delete'
  ) THEN
    CREATE POLICY "settings_delete" ON user_settings FOR DELETE USING (auth.uid() = user_id);
  END IF;
END $$;

-- ─── 4. FUNCTIONS + TRIGGERS ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgname = 'trg_user_settings_updated_at'
      AND tgrelid = 'public.user_settings'::regclass
  ) THEN
    DROP TRIGGER trg_user_settings_updated_at ON user_settings;
  END IF;
END $$;

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

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgname = 'trg_new_user_settings'
      AND tgrelid = 'auth.users'::regclass
  ) THEN
    DROP TRIGGER trg_new_user_settings ON auth.users;
  END IF;
END $$;

CREATE TRIGGER trg_new_user_settings
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION ensure_user_settings_row();
