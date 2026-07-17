-- Non-destructive migration for separate envelope logging.
-- Creates a dedicated envelope_entries table and backfills existing
-- user_settings.envelope_entries JSON if it exists.

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
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'envelope_entries'
      AND policyname = 'envelope_select'
  ) THEN
    CREATE POLICY "envelope_select" ON envelope_entries
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'envelope_entries'
      AND policyname = 'envelope_insert'
  ) THEN
    CREATE POLICY "envelope_insert" ON envelope_entries
      FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'envelope_entries'
      AND policyname = 'envelope_update'
  ) THEN
    CREATE POLICY "envelope_update" ON envelope_entries
      FOR UPDATE USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'envelope_entries'
      AND policyname = 'envelope_delete'
  ) THEN
    CREATE POLICY "envelope_delete" ON envelope_entries
      FOR DELETE USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'user_settings'
      AND column_name = 'envelope_entries'
  ) THEN
    INSERT INTO envelope_entries (
      id,
      user_id,
      date,
      category,
      description,
      amount,
      type,
      source,
      created_at,
      updated_at
    )
    SELECT
      COALESCE(entry.id, md5(entry.date || entry.category || entry.description || entry.amount::text)),
      us.user_id,
      entry.date,
      entry.category,
      COALESCE(entry.description, ''),
      entry.amount,
      COALESCE(entry.type, 'expense'),
      COALESCE(entry.source, 'envelope'),
      COALESCE(entry.created_at, NOW()),
      COALESCE(entry.updated_at, NOW())
    FROM user_settings us
    CROSS JOIN LATERAL jsonb_to_recordset(COALESCE(us.envelope_entries, '[]'::jsonb)) AS entry(
      id TEXT,
      date TEXT,
      category TEXT,
      description TEXT,
      amount NUMERIC,
      type TEXT,
      source TEXT,
      created_at TIMESTAMPTZ,
      updated_at TIMESTAMPTZ
    )
    ON CONFLICT (id, user_id) DO NOTHING;
  END IF;
END $$;
