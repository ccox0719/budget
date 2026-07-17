# Budget App — AI Audit Todo List

## Critical / Investigate First

- [x] **Transactions appear doubled** — investigate import dedup logic and `split_group_id` handling
- [x] **Kids balances/history not normalized on load** (line 424) — add fallback for missing `balances` and `history` fields on load from Supabase
- [x] **Kids payout rounding drift** (lines 3902–3907) — ensure `wallet + savings + christmas + tithe` always equals `gross` exactly
- [x] **Keyword learning doesn't block vendor matrix conflicts** (line 919) — `deriveLearnedKeywords` needs the same `matchVendor` guard added to `saveVendorMatrix`

## High Priority

- [x] **Duplicate splits on re-import** (line 1082) — dedup logic checks against prior imports but not within the current batch; same CSV imported twice can double vendor splits
- [x] **All envelope categories can be unchecked** (line 2674) — nothing prevents the user from blanking out the Envelopes view entirely
- [x] **Keyword map CSV import doesn't filter vendor conflicts** (line 3091) — keywords imported via CSV don't run through the vendor conflict check
- [x] **Sub-budget deletion orphans transactions** (line 2715) — deleting a sub-budget leaves existing transactions with stale refs in their descriptions

## Medium Priority

- [x] **CSV negative income amounts misclassified as expenses** (line 609) — refunds with negative income values get treated as expenses
- [x] **Tax item success toast fires before Supabase confirms** (line 1171) — "Item removed" shows before the delete actually completes
- [x] **Dedup logic inconsistency between manual dedup and import dedup** (lines 993–1015) — the two functions don't use the same logic

## Low Priority

- [x] **Month/year selection resets on page refresh** (lines 653–654) — not persisted to localStorage or Supabase
- [x] **Tax item custom sort order lost on refresh** (line 747) — sort order set by array index only, custom ordering not persisted
- [x] **Vendor keywords default to vendor ID if `keywords` array is missing** (line 237) — could cause unexpected broad matches
