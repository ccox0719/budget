-- Add the vendor split key column for existing projects without resetting data.
ALTER TABLE IF EXISTS public.transactions
ADD COLUMN IF NOT EXISTS vendor_split_vendor_key TEXT;

-- Ask PostgREST to refresh its schema cache so the REST API sees the new column.
NOTIFY pgrst, 'reload schema';
