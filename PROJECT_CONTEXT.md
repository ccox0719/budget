# Project Context

## What This Project Is

This repository contains **The Ledger**, a single-page React application for family budgeting and household finance tracking. It is centered around:

- envelope-style budgeting
- transaction tracking and categorization
- CSV import and reconciliation
- tax document/task tracking
- kids' chore and allowance ledger
- vendor rule and keyword-based transaction classification

The app is designed to keep finance data in Supabase while rendering a fast browser UI through Vite.

## High-Level Architecture

The project is intentionally compact:

- `src/main.jsx` is the Vite entry point
- `budget-app.jsx` contains the actual application logic and UI
- `supabase-setup.sql` defines the database schema, policies, and triggers
- `netlify.toml` handles static deployment and SPA routing

The codebase does not use a large component tree or a backend service. Instead, the React app talks directly to Supabase over HTTP using a small custom client implemented inside `budget-app.jsx`.

## Technology Stack

- React 18
- Vite
- Recharts for charts and summaries
- Bootstrap Icons for iconography
- Supabase for authentication and persistence
- Netlify for hosting

## Core Data Model

Most business data is stored in Supabase and loaded into the app on startup.

Primary tables:

- `user_settings`
  - budgets
  - keywords
  - manual review keywords
  - envelope category configuration
  - sub-budget configuration
  - kids data
  - vendor matrix
  - travel day settings
- `transactions`
  - manual transactions
  - imported CSV transactions
  - category, description, amount, source, split metadata
- `tax_items`
  - tax document checklist items

Authentication is handled through Supabase Auth. The app includes a lightweight session layer that stores auth state locally so the user stays signed in between refreshes.

## Main User Flows

### Budgeting

The budgeting area supports:

- monthly budget amounts
- envelope categories
- carryover budgets
- sub-budgets
- spending summaries and charts
- budget suggestions based on transaction history

### Transactions

The app can:

- add manual transactions
- edit category and description
- delete transactions
- import transactions from CSV
- reconcile and reclassify imported data
- infer categories from keywords and vendor rules

### Classification Rules

The app maintains:

- keyword rules for auto-categorization
- manual review keyword lists
- vendor matrices for splitting transactions across categories

These rules are used to classify new CSV rows and improve transaction matching over time.

### Tax Tracking

The tax workflow is represented as a checklist/task tracker for document collection and status tracking.

### Kids Ledger

There is a separate kids/allowance subsystem for:

- chores
- pay periods
- balance buckets
- allowance and savings tracking

## Build And Deployment

The main build and deploy flow is:

```bash
npm run build
netlify deploy --prod
```

Build output is published from `dist`, and `netlify.toml` redirects all routes to `index.html` so the SPA works with direct navigation and refreshes.

## Important Implementation Notes

- The app is heavily stateful but remains a single-page frontend.
- `budget-app.jsx` is large and contains most of the behavior in one file.
- Supabase access is done with a custom fetch-based client rather than the official Supabase JS package.
- The SQL files in the repo matter: schema, RLS policies, indexes, and triggers are part of the application design, not just setup scripts.
- The app is meant to work as a cloud-backed personal/family finance tool, not as an offline-first local app.

## Practical Working Notes

- If you change data structures in the app, update the matching Supabase schema and any migration SQL.
- If you add a new persisted feature, decide first whether it belongs in `user_settings`, `transactions`, or `tax_items`.
- If you touch auth behavior, be careful not to break the custom session flow in `budget-app.jsx`.

