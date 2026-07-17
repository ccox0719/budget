// ── Paste this in your browser's DevTools Console while the app is open ──────
// It reads your existing login session and writes directly to Supabase.
// Adds: 2026 carryover balances, income/expenses, AND chore payments.

(async () => {
  const SUPABASE_URL = "https://svaozzitkajgqzacldur.supabase.co";
  const ANON_KEY     = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN2YW96eml0a2FqZ3F6YWNsZHVyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTgyMDY1NDMsImV4cCI6MjA3Mzc4MjU0M30.zn50Iw8ib-wTt2Z0gQuKnJbDSe8qr-H-tRvkW2THiKQ";

  // Get auth token from localStorage (same place the app stores it)
  const sessionRaw = localStorage.getItem("sb-auth-token");
  const session    = sessionRaw ? JSON.parse(sessionRaw) : null;
  const token      = session?.access_token || ANON_KEY;
  const userId     = session?.user?.id;

  if (!userId) { console.error("Not logged in — open the app and sign in first."); return; }
  console.log("User ID:", userId);

  const headers = {
    "apikey":        ANON_KEY,
    "Authorization": `Bearer ${token}`,
    "Content-Type":  "application/json",
  };

  // ── Helper: split gross amount 50/20/20/10 (mirrors app logic exactly) ────────
  function splitKidAllocation(grossAmount) {
    const totalCents = Math.max(0, Math.round(grossAmount * 100));
    const weights = [
      { key:"wallet",    pct:0.50 },
      { key:"savings",   pct:0.20 },
      { key:"christmas", pct:0.20 },
      { key:"tithe",     pct:0.10 },
    ];
    const parts = weights.map(w => {
      const exact = totalCents * w.pct;
      const cents = Math.floor(exact);
      return { ...w, cents, frac: exact - cents };
    });
    let remainder = totalCents - parts.reduce((s,p) => s + p.cents, 0);
    parts.sort((a,b) => b.frac - a.frac);
    parts.forEach(p => { if (remainder-- > 0) p.cents += 1; });
    return parts.reduce((acc,p) => { acc[p.key] = p.cents/100; return acc; }, {});
  }

  function roundMoney(v) { return parseFloat(Number(v||0).toFixed(2)); }

  function getHistoryDelta(tx, key) {
    const explicit = Number(tx?.[key]);
    if (Number.isFinite(explicit)) return explicit;
    if (tx?.type === "bucketAction" && tx.bucket === key) return Number(tx.gross) || 0;
    if ((tx?.type === "gift" || tx?.type === "withdrawal") && key === "wallet") return Number(tx.gross) || 0;
    return 0;
  }

  function recalcBalances(history) {
    return history.reduce((b, tx) => ({
      wallet:    roundMoney(b.wallet    + getHistoryDelta(tx, "wallet")),
      savings:   roundMoney(b.savings   + getHistoryDelta(tx, "savings")),
      christmas: roundMoney(b.christmas + getHistoryDelta(tx, "christmas")),
      tithe:     roundMoney(b.tithe     + getHistoryDelta(tx, "tithe")),
    }), { wallet:0, savings:0, christmas:0, tithe:0 });
  }

  // ── Wallet-only transactions (carryovers, income, expenses) ──────────────────
  // gross > 0 = income/gift, gross < 0 = expense/spent
  const WALLET_TRANSACTIONS = [
    // 2025 Carryover balances
    { date:"2026-01-01", kid:"jaden", action:"gift",  description:"2025 Leftover Balance", gross:  18.24 },
    { date:"2026-01-01", kid:"kyden", action:"gift",  description:"2025 Leftover Balance", gross:  20.71 },
    { date:"2026-01-01", kid:"elsie", action:"gift",  description:"2025 Leftover Balance", gross:  20.50 },
    // Income (direct to wallet, no split)
    { date:"2026-01-04", kid:"jaden", action:"gift",  description:"Vacuum",                gross:   5.00 },
    { date:"2026-01-18", kid:"jaden", action:"gift",  description:"Vacuum",                gross:   3.00 },
    { date:"2026-01-18", kid:"kyden", action:"gift",  description:"Vacuum",                gross:   2.00 },
    { date:"2026-01-30", kid:"kyden", action:"gift",  description:"Church childcare",      gross:  12.00 },
    { date:"2026-02-16", kid:"jaden", action:"gift",  description:"Tip from Culver's",     gross:  15.00 },
    { date:"2026-02-26", kid:"jaden", action:"gift",  description:"Tip from Culver's",     gross:  15.00 },
    // Expenses
    { date:"2026-02-06", kid:"jaden", action:"spent", description:"Lunch",                 gross: -15.00 },
    { date:"2026-02-19", kid:"jaden", action:"spent", description:"Lunch",                 gross: -10.00 },
    { date:"2026-02-19", kid:"kyden", action:"spent", description:"Lunch",                 gross:  -4.00 },
    { date:"2026-02-26", kid:"jaden", action:"spent", description:"Bleach kit",            gross: -18.00 },
  ];

  // ── Chore payments (split 50/20/20/10 across wallet/savings/christmas/tithe) ─
  // Rates: Floor $1, Sink $0.50, Mirror $0.50, Bathtub $1, Toilet $1, Laundry $2
  const CHORE_PAYMENTS = [
    {
      kid: "jaden",
      date: "2026-03-21",
      // Sink×9=$4.50, Mirror×9=$4.50, Bathtub×1=$1, Toilet×1=$1, Laundry×9=$18 → $29.00
      gross: 29.00,
      description: "Chores: Bathroom Sink x9, Bathroom Mirror x9, Bathroom Bathtub, Bathroom Toilet, Laundry x9",
    },
    {
      kid: "kyden",
      date: "2026-03-21",
      // Sink×9=$4.50, Mirror×9=$4.50, Bathtub×1=$1, Toilet×1=$1, Laundry×9=$18 → $29.00
      gross: 29.00,
      description: "Chores: Bathroom Sink x9, Bathroom Mirror x9, Bathroom Bathtub, Bathroom Toilet, Laundry x9",
    },
    {
      kid: "elsie",
      date: "2026-03-21",
      // Floor×1=$1, Toilet×7=$7, Laundry×8=$16 → $24.00
      gross: 24.00,
      description: "Chores: Bathroom Floor, Bathroom Toilet x7, Laundry x8",
    },
  ];

  // ── Fetch current kids_data ───────────────────────────────────────────────────
  const fetchRes = await fetch(
    `${SUPABASE_URL}/rest/v1/user_settings?user_id=eq.${userId}&select=kids_data`,
    { headers }
  );
  const rows = await fetchRes.json();
  if (!Array.isArray(rows) || rows.length === 0) {
    console.error("Could not fetch user_settings:", rows);
    return;
  }

  const kids_data = rows[0].kids_data;
  if (!Array.isArray(kids_data)) { console.error("kids_data missing or not an array"); return; }
  console.log("Current kids:", kids_data.map(k => `${k.name}: wallet=$${k.balances?.wallet} savings=$${k.balances?.savings} christmas=$${k.balances?.christmas} tithe=$${k.balances?.tithe}`).join("\n  "));

  // ── Build new history entries for each kid ────────────────────────────────────
  const newEntriesByKid = {};

  // Wallet transactions
  WALLET_TRANSACTIONS.forEach((tx, i) => {
    const k = tx.kid;
    if (!newEntriesByKid[k]) newEntriesByKid[k] = [];
    newEntriesByKid[k].push({
      id:          `k-import-${k}-${tx.date.replace(/-/g,"")}-w${i}`,
      date:        tx.date,
      type:        "bucketAction",
      bucket:      "wallet",
      action:      tx.action,
      description: tx.description,
      gross:       tx.gross,
      wallet:      tx.gross,
      savings:     0,
      christmas:   0,
      tithe:       0,
    });
  });

  // Chore payments (split)
  CHORE_PAYMENTS.forEach((cp, i) => {
    const k = cp.kid;
    if (!newEntriesByKid[k]) newEntriesByKid[k] = [];
    const split = splitKidAllocation(cp.gross);
    newEntriesByKid[k].push({
      id:          `k-import-${k}-${cp.date.replace(/-/g,"")}-c${i}`,
      date:        cp.date,
      type:        "chores",
      description: cp.description,
      gross:       cp.gross,
      wallet:      split.wallet,
      savings:     split.savings,
      christmas:   split.christmas,
      tithe:       split.tithe,
    });
  });

  // ── Merge, sort, recalculate per kid ─────────────────────────────────────────
  const updatedKids = kids_data.map(kid => {
    const kidId = (kid.id || kid.name || "").toLowerCase();
    const newEntries = newEntriesByKid[kidId] || [];
    if (newEntries.length === 0) return kid;

    const combinedHistory = [...(kid.history || []), ...newEntries]
      .sort((a, b) => {
        const d = new Date(a.date) - new Date(b.date);
        return d !== 0 ? d : String(a.id).localeCompare(String(b.id));
      });

    const newBalances = recalcBalances(combinedHistory);

    console.log(
      `\n  ${kid.name} (${newEntries.length} new entries):\n` +
      `    wallet:    $${kid.balances?.wallet ?? "?"} → $${newBalances.wallet}\n` +
      `    savings:   $${kid.balances?.savings ?? "?"} → $${newBalances.savings}\n` +
      `    christmas: $${kid.balances?.christmas ?? "?"} → $${newBalances.christmas}\n` +
      `    tithe:     $${kid.balances?.tithe ?? "?"} → $${newBalances.tithe}`
    );

    return { ...kid, history: combinedHistory, balances: newBalances };
  });

  // ── Write back (upsert — same method the app uses) ────────────────────────────
  console.log("\nWriting to Supabase...");
  const saveRes = await fetch(
    `${SUPABASE_URL}/rest/v1/user_settings`,
    {
      method:  "POST",
      headers: { ...headers, "Prefer": "resolution=merge-duplicates,return=minimal" },
      body:    JSON.stringify({ user_id: userId, kids_data: updatedKids }),
    }
  );

  if (saveRes.ok) {
    console.log("✅ Done! Refresh the app to see the updated ledger.");
  } else {
    const err = await saveRes.text();
    console.error("❌ Save failed:", saveRes.status, err);
  }
})();
