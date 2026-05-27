# Data Monetisation — Early_Tech_Adopters segment

A privacy-safe audience segment that identifies customers who **buy or show strong interest in newly launched technology shortly after release**. Built for the Data Monetisation team so partners can run launch-window campaigns, train AI models, and surface insights without touching personal data.

This repo contains:

- The SQL that **builds the segment** and **validates it** — see `early_adopters.sql`
- The script that **loads the source CSVs** into Postgres — see `load_vmo2db.sql`
- A deeper write-up of assumptions, results, and follow-ups — see `study.md`
- The brief itself — `Data Monetization - Early tech adopters Brief.pdf`

---

## Data snapshot

Source files live in `early_tech_adopter_dataset/`. Loaded into a local Postgres database `VMO2db` (`127.0.0.1:5431`).

| Table | Rows | What one row is | Key columns |
|---|---:|---|---|
| `product_catalog` | 2,000 | One SKU | `sku`, `product_name`, `category`, `launch_date` |
| `profiles` | 20,000 | One profile snapshot per user | `user_id`, `snapshot_date`, `prefers_new_releases`, `trade_in_member` |
| `orders` | 55,000 | One purchased SKU | `user_id`, `order_ts`, `sku`, `price` |
| `sku_views` | 55,000 | One product pageview | `user_id`, `event_ts`, `sku` |

**Coverage**

- `product_catalog.launch_date` spans **2024-01-01 → 2026-06-18**
- `orders.order_ts` and `sku_views.event_ts` both span **2026-01-01 → 2026-06-30**
- `profiles` has one snapshot per `user_id` (snapshot_date = 2026-02-10 for the whole population)
- Categories observed: `accessory`, `audio`, `gaming`, `laptop`, `smart_home`, `smartphone`, `tablet`, `wearable`
- `profiles.prefers_new_releases` has ~6.5k NULL values (column is nullable for that reason)

---

## Tasks (from the brief)

The brief defines three tasks the data engineer must complete.

### Task 1 — Define the segment

Write an auditable SQL query that returns **one row per user** with:

- `user_id`
- `early_adopter_flag` (TRUE / FALSE)
- `evidence_source` (which rule(s) triggered the flag)

A user is flagged if **any** of the following signals apply:

1. **Purchase behaviour** — purchased a "latest" SKU within 90 days of launch.
2. **Interest behaviour** — viewed the same "latest" SKU at least 2 times within 30 days of launch.
3. **Profile support (secondary evidence)** — `prefers_new_releases = TRUE` or `trade_in_member = TRUE`.

### Task 2 — Sanity-check the segment

- Count of early adopters and share of total **active users** (any event in the last 90 days).
- Breakdown by `evidence_source` and by **product category**.

### Task 3 — Plain-English explanation

2–3 lines explaining how the rules identify "early tech" behaviour and why the logic is sensible for commercial monetisation.

---

## Solution overview

The full implementation is in **`early_adopters.sql`** (segment view + three validation queries). The walkthrough, decisions, and results are in **`study.md`**. This section explains the *shape* of the solution — what was built and why.

### Design decisions (locked in before writing SQL)

| # | Question | Decision |
|---|---|---|
| 1 | Does Rule 3 (profile) flag a user on its own? | **No** — profile signals are *supporting evidence only*. A user is flagged only if Rule 1 OR Rule 2 fires. Profile can still appear in `evidence_source` when it co-occurs. The brief calls Rule 3 "secondary", which drove this call. |
| 2 | What does "latest" SKU mean? | Every SKU is evaluated in its **own** 30/90-day post-launch window. No global recency cutoff — a 2024 SKU still counts as "latest" for events within 30/90 days of *its* launch_date. Simplest reading of the brief. |
| 3 | Reference date for "last 90 days" active users? | `CURRENT_DATE` — queries treat the world as "live" today. |

Minor calls: "within N days of launch" is inclusive both ends by date; "≥2 views" means 2 view events on the same `(user, sku)` inside the 30-day window; `evidence_source` is a comma-separated tag set (`purchase`, `view`, `profile`) or `NULL` for non-adopters.

### How the segment SQL is structured

The segment is built as a Postgres **view** (`early_tech_adopters`) so the validation queries can join to it without recomputing. The view is composed of small, named CTEs — one per rule — so a reviewer can run any rule on its own to audit which users it captures:

1. `rule1_purchase` — distinct users who purchased a SKU in its 90-day post-launch window.
2. `rule2_view` — distinct users with ≥2 views on the same SKU inside its 30-day post-launch window.
3. `rule3_profile` — distinct users with a positive profile flag.
4. `all_users` — superset (union of `profiles`, `orders`, `sku_views`) so non-adopters get a row too.
5. `flags` — left-joins each rule onto `all_users` to produce three booleans per user.
6. Final select — applies the gating rule (`r1 OR r2`) and assembles the `evidence_source` tag string, including `profile` only when it co-occurs with a behavioural signal.

### Validation queries

Three follow-on queries in the same file:

- **2a.** Compares `total_early_adopters` to `total_active_users` (active = any event in last 90 days from `CURRENT_DATE`) and reports the percentage.
- **2b.** Counts flagged users grouped by `evidence_source` string — surfaces which rule combinations are doing the work.
- **2c.** For each product category × triggering rule, counts distinct flagged users — shows whether the segment is balanced across the catalog.

### Headline results (run on 2026-05-27)

- **4,970 early adopters** out of 19,551 active users → **25.24 %** of active users.
- Evidence mix: `purchase,profile` 3,327 · `purchase` 1,643.
- Category leaders: `accessory` (927), `gaming` (831), `wearable` (747).
- **Rule 2 (view ≥2× in 30 days) never fires in this dataset** — only 33 `(user, sku)` pairs have ≥2 views anywhere in `sku_views`, and none are inside a post-launch window. Logged as a data-quality follow-up in `study.md`; not a SQL bug.

---

## How to run

The Postgres instance is expected at `127.0.0.1:5431`, database `VMO2db`, user `postgres`.

```bash
# 1. Load the CSVs into VMO2db
psql -h 127.0.0.1 -p 5431 -d VMO2db -U postgres -f load_vmo2db.sql

# 2. Build the view and run the validation queries
psql -h 127.0.0.1 -p 5431 -d VMO2db -U postgres -f early_adopters.sql
```

After step 2, the segment is available as a view:

```sql
SELECT * FROM early_tech_adopters WHERE early_adopter_flag LIMIT 20;
```

---

## Files in this repo

| File | Purpose |
|---|---|
| `README.md` | This document — orientation, snapshot, and solution overview |
| `study.md` | Full write-up: decisions, query rationale, validation results, follow-ups *(gitignored)* |
| `early_adopters.sql` | Segment view + Task 2 validation queries |
| `load_vmo2db.sql` | Creates the four tables and ingests CSVs |
| `early_tech_adopter_dataset/` | Source CSV files |
| `Data Monetization - Early tech adopters Brief.pdf` | Original brief |
