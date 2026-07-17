# Supabase Persistence & Cross-Device Sync Audit
**App:** Family Budget / Envelope Tracker
**Date:** 2026-03-17
**File audited:** `budget-app.jsx` (~4,200 lines, single-file React app)

---

## A. Executive Summary

The good news: **all meaningful business data was already being written to Supabase.** The bad news: **Device B had no way to see those changes until you manually reloaded the page.** There were no silent data-loss bugs — but there were three categories of sync problems:

**1. No cross-device refresh mechanism (root cause of both reported bugs)**
The app fetched data exactly once — on mount — and never again. A change made on Device A (toggle, CSV import, budget edit) was persisted to Supabase correctly, but Device B, already open in the browser, had no trigger to re-read the database. The only fix was a hard page reload.

**2. Toggle side-effects inside React setState updaters (React anti-pattern)**
Both `toggleEnvelopeCategory` and `toggleSubBudgetEnvelope` in `BudgetsView` called `onSave()` (which writes to Supabase) *inside* a `setState` updater function. React's contract says updater functions must be pure and may run more than once (especially in Strict Mode / React 18 dev). This could cause duplicate Supabase writes on toggle in development, and is architecturally fragile.

**3. Fire-and-forget mutations with no error feedback**
Every single Supabase write used the pattern `.then(({ error }) => { if (error) console.error(error) })`. If any write failed due to a network hiccup, RLS block, or auth expiry, the user saw "Saved ✓" in the toast while the data silently failed to persist. There was no retry, no user-visible error, and no way to know something went wrong without opening DevTools.

---

## B. Persistence Audit Table

| Feature | Entity | Action | Was Being Saved? | Problem | Severity |
|---------|--------|--------|-----------------|---------|----------|
| Envelopes | `envelope_category_ids` | Toggle On/Off | ✅ Yes | No cross-device refresh. Side effect inside setState. | **High** |
| Sub-budget envelopes | `sub_budgets[].envelopeOn` | Toggle On/Off | ✅ Yes | Same as above | **High** |
| CSV Import | `transactions` | Import rows | ✅ Yes | No cross-device refresh (Device B never sees import) | **High** |
| Budget amounts | `budgets` | Edit & Save | ✅ Yes | No cross-device refresh | **High** |
| Income | `income` | Edit & Save | ✅ Yes | No cross-device refresh | **High** |
| Keywords | `keywords` | Edit & Save | ✅ Yes | No cross-device refresh | **Medium** |
| Kids / Chores | `kids_data` | Pay week, edits | ✅ Yes | No cross-device refresh. Error silently swallowed. | **High** |
| Vendor Matrix | `vendor_matrix` | Edit & Save | ✅ Yes | No cross-device refresh. Error silently swallowed. | **Medium** |
| Transactions (manual) | `transactions` | Add | ✅ Yes | Error silently swallowed | **Medium** |
| Transactions | `transactions` | Delete | ✅ Yes | Error silently swallowed | **Medium** |
| Transactions | `transactions` | Edit category | ✅ Yes | Error silently swallowed | **Medium** |
| Transactions | `transactions` | Edit description | ✅ Yes | Error silently swallowed | **Medium** |
| Tax items | `tax_items` | Add/Edit/Delete | ✅ Yes | Error silently swallowed | **Medium** |
| Classification (reclassify) | `transactions.category` | Re-classify CSV | ✅ Yes | Dead code in callback (unreachable) | **Low** |
| Dark mode | `localStorage` | Toggle | ✅ Yes (local-only) | Intentional — device preference, not shared data | None |
| UI state (view, month, etc.) | In-memory | Navigation | n/a | Intentional — not persisted, correct behavior | None |
| Import preview | In-memory | Staging CSV | n/a | Intentional — cleared after confirm | None |

---

## C. Complete Findings

### Finding 1 — No cross-device sync after initial load
**Severity:** Critical
**Files:** `budget-app.jsx`, `FinanceApp` component, lines 621–696 (original)

**What was wrong:**
All data was fetched once inside a `useEffect` with `[userId]` dependency. After that initial load, nothing triggered a re-fetch. If Device A toggled the envelope on and saved to Supabase, Device B (already loaded) had stale in-memory state with no mechanism to update it.

**Why it fails:**
The app had no real-time subscriptions (Supabase Realtime was not set up) and no polling. The only way to see changes from another device was a full browser reload.

**Fix applied:**
Extracted the data-load code into a ref-backed function `_loadRef.current(isInitialLoad)`. Added a second `useEffect` that attaches `visibilitychange` and `focus` event listeners. When the user switches back to the browser tab or window after being away, it silently re-fetches settings and transactions from Supabase. A 10-second debounce prevents flooding the DB when rapidly alt-tabbing.

```js
// New: Cross-device sync via visibility/focus re-fetch
useEffect(()=>{
  if (!loaded) return;
  let lastRefreshTs = 0;
  const doRefresh = () => {
    const ts = Date.now();
    if (ts - lastRefreshTs < 10000) return; // debounce: max once per 10 s
    lastRefreshTs = ts;
    _loadRef.current(false);   // false = don't re-seed defaults
  };
  const onVisible = () => { if (!document.hidden) doRefresh(); };
  document.addEventListener("visibilitychange", onVisible);
  window.addEventListener("focus", doRefresh);
  return () => {
    document.removeEventListener("visibilitychange", onVisible);
    window.removeEventListener("focus", doRefresh);
  };
}, [loaded]);
```

**How to verify:**
1. Open the app on Desktop and on Phone (same account).
2. On Desktop, toggle an envelope on.
3. On Phone, switch to another app and back (triggering `visibilitychange`).
4. The envelope toggle appears on Phone without a manual reload.

---

### Finding 2 — Side effects inside React setState updaters
**Severity:** High (React anti-pattern, causes double-write in Strict Mode)
**Files:** `budget-app.jsx`, `BudgetsView` component

**What was wrong:**
```js
// BEFORE — broken pattern
function toggleEnvelopeCategory(catId) {
  setLe(current => {
    const next = current.includes(catId)
      ? current.filter(id => id !== catId)
      : [...current, catId];
    onSave(lb, li, next, lsb);  // ← side effect inside updater!
    return next;
  });
}
```
React requires state updater functions to be pure (no side effects). In React 18's Strict Mode (development), updaters intentionally run twice to surface this bug. This means `onSave` — and therefore the Supabase `upsert` — could fire twice per toggle click in dev builds.

**Fix applied:**
Moved the `onSave` call out of the updater. Since there are no concurrent state updates to `le` or `lsb`, reading directly from the closure is safe:

```js
// AFTER — correct pattern
function toggleEnvelopeCategory(catId) {
  const next = le.includes(catId)
    ? le.filter(id => id !== catId)
    : [...le, catId];
  setLe(next);
  onSave(lb, li, next, lsb);  // ← called after setState, outside updater
}
```

Same fix applied to `toggleSubBudgetEnvelope`.

---

### Finding 3 — Silent save failures (fire-and-forget everywhere)
**Severity:** Medium-High
**Files:** `budget-app.jsx`, all mutation functions

**What was wrong:**
Every Supabase write in the codebase used this pattern:
```js
supabase.from("...").insert({ ... })
  .then(({ error }) => { if (error) console.error("tag:", error); });
```
If the write failed (network drop, RLS block, expired token, rate limit), the error was only logged to the console. The user received a "Saved ✓" toast from the optimistic update while their data was silently lost.

**Fix applied:**
Updated all 12 mutation call sites to show a visible error toast on failure:
```js
.then(({ error }) => {
  if (error) { console.error("saveSettings:", error); showToast("⚠️ Save failed — check connection"); }
});
```

Affected functions: `saveSettings`, `saveVendorMatrix`, `updateKids`, `addTransactionDirect`, `addTransaction`, `updateCategory`, `updateTransactionDesc`, `deleteTransaction`, `confirmImport`, `updateTaxItem`, `addTaxItem`, `deleteTaxItem`.

---

### Finding 4 — Dead unreachable code in `onReclassify` callback
**Severity:** Low (code quality / confusion)
**Files:** `budget-app.jsx`, KeywordsView callback, ~line 1492

**What was wrong:**
```js
onReclassify={()=>{
  reclassifyCsvTransactions({ includeLearn:true });
  return;                          // ← early return
  const prev=transactions;         // ← DEAD CODE — never runs
  const updated=prev.map(...);
  // ...
  showToast("Re-classified ✓");
}}
```
A previous refactor moved logic into `reclassifyCsvTransactions()` but left the old inline implementation below a `return` statement. It was never executed.

**Fix applied:** Removed the 11 dead lines. The callback is now a clean one-liner.

---

## D. Fix Plan (by priority)

### Priority 1 — Cross-device data inconsistency (FIXED ✅)
- Refresh-on-visibility / focus (Finding 1)
- Toggle setState anti-pattern (Finding 2)

### Priority 2 — Silent data loss on save failures (FIXED ✅)
- Error toast on all Supabase write failures (Finding 3)

### Priority 3 — Code quality (FIXED ✅)
- Remove dead code in reclassify callback (Finding 4)

### Priority 4 — Future improvements (not implemented, lower risk)
These are recommended next steps but do not represent current data-loss bugs:

- **Supabase Realtime subscription** — The current fix (refresh-on-focus) handles the most common cross-device use case. For true live sync (two devices open side by side), you'd add a `user_settings` Realtime subscription. Requires extending the custom Supabase client with WebSocket support or switching to the official `@supabase/supabase-js` SDK.
- **Retry logic for failed writes** — Currently, if a save fails, the user sees an error toast but data is NOT rolled back from in-memory state. If they navigate away and reload, their change will be lost. A retry queue or "pending changes" indicator would close this gap.
- **RLS audit** — The schema uses `auth.uid() = user_id` on all tables. If the JWT expires mid-session (sessions are 1 hour), writes will silently fail (now with a toast) until re-auth. Consider adding token-expiry detection.

---

## E. State Architecture Summary

### Source of truth — correctly Supabase-backed
| Data | Supabase table | Column |
|------|---------------|--------|
| Budget amounts | `user_settings` | `budgets` (JSONB) |
| Income | `user_settings` | `income` |
| Envelope category IDs | `user_settings` | `envelope_category_ids` (JSONB) |
| Sub-budget config + envelope flags | `user_settings` | `sub_budgets` (JSONB) |
| Keywords / classification rules | `user_settings` | `keywords` (JSONB) |
| Kids data / chores / balances | `user_settings` | `kids_data` (JSONB) |
| Vendor matrix | `user_settings` | `vendor_matrix` (JSONB) |
| All transactions (manual + CSV) | `transactions` | full row |
| Tax document tracker | `tax_items` | full row |

### Source of truth — intentionally local-only (correct)
| Data | Storage | Reason |
|------|---------|--------|
| Dark mode | `localStorage` | Per-device preference |
| Current view (tab) | In-memory state | Transient navigation state |
| Selected month/year | In-memory state | Transient UI state |
| CSV import preview | In-memory state | Staging only — discarded or committed |
| Auth session token | `localStorage` | Standard auth pattern |

---

## F. Sync Safety Standards (going forward)

1. **No business data in component state only.** After any save, data must exist in Supabase, not just in React state.
2. **Every mutation must handle errors visibly.** `.then(({ error }) => showToast("⚠️ ..."))` is the minimum. Never swallow errors silently.
3. **Never call side effects (API calls, toasts, etc.) inside `setState` updater functions.** Updaters must be pure.
4. **Refresh-on-focus is now active.** All data re-syncs when the user returns to the app. Don't bypass this by adding local-only caches.
5. **Optimistic updates are acceptable for UX**, but the UI should reflect if the write failed (currently handled by error toast).
6. **Imported CSV rows are real transactions.** They are inserted into `transactions` with `source: "csv"` and are fully cloud-backed. They are not staged anywhere locally after `confirmImport()`.

---

## G. Cross-Device Verification Checklist

Use this to confirm each feature syncs correctly after these fixes:

- [ ] Toggle "Envelope On" on Desktop → switch to Phone tab → envelope appears (within 10 s of switching back)
- [ ] Import CSV on Desktop → switch to Phone tab → transactions appear
- [ ] Edit budget amount on Desktop, save → switch to Phone → amount is correct
- [ ] Add a chore payment on Phone → switch to Desktop → balance updated
- [ ] Edit a keyword on Desktop → save → switch to Phone → keyword visible
- [ ] Manually add a transaction on Phone → switch to Desktop → transaction visible
- [ ] Delete a transaction on Desktop → switch to Phone → transaction gone
- [ ] Toggle sub-budget envelope on Desktop → switch to Phone → toggle reflected
- [ ] Sign out and sign back in on both devices → all data matches

---

*Report generated by automated codebase audit. All findings above have been implemented in `budget-app.jsx`.*
