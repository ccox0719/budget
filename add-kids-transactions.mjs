// Script to add kids ledger transactions directly to Supabase.
// Usage (PowerShell):
//   $env:SUPABASE_KEY = "<service_role_or_user_token>"
//   node add-kids-transactions.mjs
// Optional:
//   $env:SUPABASE_URL = "https://<project-ref>.supabase.co"
//   $env:SUPABASE_USER_ID = "<uuid>"

const SUPABASE_URL = process.env.SUPABASE_URL || "https://svaozzitkajgqzacldur.supabase.co";
const ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN2YW96eml0a2FqZ3F6YWNsZHVyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTgyMDY1NDMsImV4cCI6MjA3Mzc4MjU0M30.zn50Iw8ib-wTt2Z0gQuKnJbDSe8qr-H-tRvkW2THiKQ";
const API_KEY = process.env.SUPABASE_KEY || ANON_KEY;
const TARGET_USER_ID = process.env.SUPABASE_USER_ID || "";

const headers = {
  apikey: API_KEY,
  Authorization: `Bearer ${API_KEY}`,
  "Content-Type": "application/json",
  Prefer: "return=representation",
};

const NEW_TRANSACTIONS = [
  { date: "2026-01-01", kid: "jaden", type: "bucketAction", bucket: "wallet", action: "gift", description: "2025 Leftover Balance", gross: 18.24 },
  { date: "2026-01-01", kid: "kyden", type: "bucketAction", bucket: "wallet", action: "gift", description: "2025 Leftover Balance", gross: 20.71 },
  { date: "2026-01-01", kid: "elsie", type: "bucketAction", bucket: "wallet", action: "gift", description: "2025 Leftover Balance", gross: 20.50 },
  { date: "2026-01-04", kid: "jaden", type: "bucketAction", bucket: "wallet", action: "gift", description: "Vacuum", gross: 5.0 },
  { date: "2026-01-18", kid: "jaden", type: "bucketAction", bucket: "wallet", action: "gift", description: "Vacuum", gross: 3.0 },
  { date: "2026-01-18", kid: "kyden", type: "bucketAction", bucket: "wallet", action: "gift", description: "Vacuum", gross: 2.0 },
  { date: "2026-01-30", kid: "kyden", type: "bucketAction", bucket: "wallet", action: "gift", description: "Church childcare", gross: 12.0 },
  { date: "2026-02-16", kid: "jaden", type: "bucketAction", bucket: "wallet", action: "gift", description: "Tip from Culver's", gross: 15.0 },
  { date: "2026-02-26", kid: "jaden", type: "bucketAction", bucket: "wallet", action: "gift", description: "Tip from Culver's", gross: 15.0 },
  { date: "2026-02-06", kid: "jaden", type: "bucketAction", bucket: "wallet", action: "spent", description: "Lunch", gross: -15.0 },
  { date: "2026-02-19", kid: "jaden", type: "bucketAction", bucket: "wallet", action: "spent", description: "Lunch", gross: -10.0 },
  { date: "2026-02-19", kid: "kyden", type: "bucketAction", bucket: "wallet", action: "spent", description: "Lunch", gross: -4.0 },
  { date: "2026-02-26", kid: "jaden", type: "bucketAction", bucket: "wallet", action: "spent", description: "Bleach kit", gross: -18.0 },
];

function roundMoney(v) {
  return parseFloat(Number(v || 0).toFixed(2));
}

function getHistoryDelta(tx, key) {
  const explicit = Number(tx?.[key]);
  if (Number.isFinite(explicit)) return explicit;
  if (tx?.type === "bucketAction" && tx.bucket === key) return Number(tx.gross) || 0;
  if ((tx?.type === "gift" || tx?.type === "withdrawal") && key === "wallet") return Number(tx.gross) || 0;
  return 0;
}

function recalcBalances(history) {
  return history.reduce(
    (b, tx) => ({
      wallet: roundMoney(b.wallet + getHistoryDelta(tx, "wallet")),
      savings: roundMoney(b.savings + getHistoryDelta(tx, "savings")),
      christmas: roundMoney(b.christmas + getHistoryDelta(tx, "christmas")),
      tithe: roundMoney(b.tithe + getHistoryDelta(tx, "tithe")),
    }),
    { wallet: 0, savings: 0, christmas: 0, tithe: 0 }
  );
}

function toHistoryEntry(kidId, tx, i) {
  return {
    id: `k-import-${kidId}-${tx.date.replace(/-/g, "")}-${i}`,
    date: tx.date,
    type: tx.type,
    bucket: tx.bucket,
    action: tx.action,
    description: tx.description,
    gross: tx.gross,
    wallet: tx.bucket === "wallet" ? tx.gross : 0,
    savings: tx.bucket === "savings" ? tx.gross : 0,
    christmas: tx.bucket === "christmas" ? tx.gross : 0,
    tithe: tx.bucket === "tithe" ? tx.gross : 0,
  };
}

async function main() {
  const query = TARGET_USER_ID
    ? `/rest/v1/user_settings?user_id=eq.${TARGET_USER_ID}&select=user_id,kids_data`
    : "/rest/v1/user_settings?select=user_id,kids_data";

  const res = await fetch(`${SUPABASE_URL}${query}`, { headers });
  const rows = await res.json();

  if (!Array.isArray(rows) || rows.length === 0) {
    console.error("No user_settings rows found or access denied:", rows);
    process.exit(1);
  }

  console.log(`Found ${rows.length} user setting row(s).`);

  const txByKid = {};
  for (const tx of NEW_TRANSACTIONS) {
    if (!txByKid[tx.kid]) txByKid[tx.kid] = [];
    txByKid[tx.kid].push(tx);
  }

  for (const row of rows) {
    const { user_id, kids_data } = row;
    if (!Array.isArray(kids_data) || kids_data.length === 0) {
      console.log(`  user ${user_id}: no kids_data, skipping`);
      continue;
    }

    const kidNames = kids_data.map(k => k.id || k.name);
    const hasFamilyKids = kidNames.some(n => ["jaden", "kyden", "elsie"].includes(String(n).toLowerCase()));
    if (!hasFamilyKids) {
      console.log(`  user ${user_id}: kids do not match (${kidNames.join(", ")}), skipping`);
      continue;
    }

    console.log(`  user ${user_id}: updating kids_data...`);

    const updatedKids = kids_data.map(kid => {
      const kidId = (kid.id || kid.name || "").toLowerCase();
      const kidTxs = txByKid[kidId] || [];
      if (kidTxs.length === 0) return kid;

      const existingHistory = Array.isArray(kid.history) ? kid.history : [];
      const existingIds = new Set(existingHistory.map(h => String(h?.id || "")));
      const newEntries = kidTxs
        .map((tx, i) => toHistoryEntry(kidId, tx, i))
        .filter(entry => !existingIds.has(entry.id));

      const combinedHistory = [...existingHistory, ...newEntries].sort((a, b) => {
        const d = new Date(a.date) - new Date(b.date);
        if (d !== 0) return d;
        return String(a.id).localeCompare(String(b.id));
      });

      const newBalances = recalcBalances(combinedHistory);
      console.log(
        `    ${kid.name || kidId}: wallet ${kid.balances?.wallet ?? "?"} -> ${newBalances.wallet} (added ${newEntries.length} new entries)`
      );

      return { ...kid, history: combinedHistory, balances: newBalances };
    });

    const updateRes = await fetch(`${SUPABASE_URL}/rest/v1/user_settings?user_id=eq.${user_id}`, {
      method: "PATCH",
      headers,
      body: JSON.stringify({ kids_data: updatedKids }),
    });

    const body = await updateRes.text();
    if (updateRes.ok) {
      console.log(`    saved (HTTP ${updateRes.status})`);
    } else {
      console.error(`    failed (HTTP ${updateRes.status}):`, body);
    }
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
