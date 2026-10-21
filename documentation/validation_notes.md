# Insurance Claims & Risk Analytics — Validation Notes

This document records the evidence available for the synthetic-data portfolio, the expected reconciliation results, and the workflow for repeating validation. Documentation prepared: **2026-10-21**. This is not the date of a new database run.

## 1. Validation status and evidence

| Evidence stage | Supported conclusion | Boundary |
| --- | --- | --- |
| Original static review | `STATIC_CHECKS(1).json` reports **passed** for text/structure checks. | No database connection, MySQL parser, or SQL execution was used. This does not prove runtime success or correct results. |
| Later project-owner execution | The owner personally ran the SQL queries in **MySQL Workbench** and reported that all expected reconciliation outputs matched. The owner-confirmed benchmarks are recorded below. | This is user-reported execution, not an independent rerun. A general confirmation does not establish the result of every null, duplicate, orphan, or edge-case check. |
| Preparation of these notes | The supplied notes, static report, four scripts, and existing methodology/data dictionary were reviewed; benchmark arithmetic was cross-checked. | No new SQL execution, database inspection, Power BI model inspection, or dashboard refresh was performed for this document. |

The original notes' statement that execution was unconfirmed describes the **earlier static-review stage**. The owner's later execution report is a separate evidence stage. Neither stage supports a claim of exhaustive QA. Detailed saved result exports, execution dates, warnings, and a complete check-by-check acceptance record are not established by the supplied evidence.

## 2. Source files and execution order

The previously uploaded `VALIDATION_NOTES(1).md` and `STATIC_CHECKS(1).json` are the source review records. Local downloaded copies contain a space before `(1)`; their contents match the corresponding unsuffixed SQL-package copies. The download suffix is not a validated dataset version.

| Order | Repository SQL file | Purpose |
| --- | --- | --- |
| 1 | [`01_data_quality.sql`](../sql/01_data_quality.sql) | Schema inspection; row counts; duplicate, null/blank, category, amount/date, and orphan profiling. DQ06 contains explicitly labeled additional null checks. |
| 2 | [`02_cleaned_views.sql`](../sql/02_cleaned_views.sql) | Create four views and perform view checks. Uses `CREATE VIEW`, not `CREATE OR REPLACE VIEW`. |
| 3 | [`03_claims_risk_analysis.sql`](../sql/03_claims_risk_analysis.sql) | Claims profile, coverage/delay flags, overlaps, score distributions, segments, ratios, and rankings. |
| 4 | [`04_payment_performance.sql`](../sql/04_payment_performance.sql) | Recorded payment counts, status/method mix, total amounts, and status-labeled amounts. |

The static report lists **29 mapped source sections** and **four view definitions**:

| Script | Statements reported | Lines reported |
| --- | ---: | ---: |
| 01 | 28 | 449 |
| 02 | 10 | 158 |
| 03 | 21 | 474 |
| 04 | 5 | 69 |

The original review covered section/source mapping, preserved extracted query text, view definitions, statement allowlists, delimiter/quote structure, and source hashes. These are structural checks, not runtime result tests. Read these notes alongside [`methodology.md`](methodology.md) and [`data_dictionary.md`](data_dictionary.md). The later owner-confirmed payment benchmarks below supplement the earlier methodology's narrower evidence scope.

## 3. Expected owner-confirmed snapshot

These are historical reconciliation benchmarks reported by the owner, not fresh outputs produced while writing this file. A changed dataset may legitimately produce different values; record its snapshot before comparing.

### Base-table counts

| Table | Expected rows |
| --- | ---: |
| `customers` | 10,000 |
| `policies` | 18,000 |
| `claims` | 25,000 |
| `payments` | 80,000 |

These counts do not independently prove key uniqueness, completeness, or referential integrity. In particular, 25,000 raw claims does not automatically establish 25,000 distinct matched claims in the analytical view.

### Claims reconciliation

| Indicator | Expected result |
| --- | ---: |
| Claims exceeding recorded policy coverage | 21 |
| Claims with `processing_days > 60` | 320 |
| Claims meeting both rules | 0 |
| Unique claims meeting either rule | 341 |
| Flagged percentage, displayed to two decimals | 1.36% |

```text
unique flagged claims = 21 + 320 - 0 = 341
flagged percentage    = 341 / 25000 * 100 = 1.364% → 1.36%
coverage percentage  = 21 / 25000 * 100 = 0.084%
delay percentage     = 320 / 25000 * 100 = 1.280%
```

The following score distribution is **derived from these benchmarks**, assuming all 25,000 claims appear exactly once in the analytical population. It is not an additional independently observed result set.

| Score | Category | Derived count | Display percentage |
| --- | --- | ---: | ---: |
| 0 | No Flag | 24,659 | 98.64% |
| 1 | Processing Flag | 320 | 1.28% |
| 2 | Coverage Flag | 21 | 0.08% |
| 3 | Multiple Flags | 0 | 0.00% |

C08 groups observed scores, so score 3 may be absent from its result rather than returned as an explicit zero row. Claim-status counts are not supplied here; obtain them from C01 and C06 rather than inventing counts for `Approved`, `Denied`, or `Pending`.

### Recorded payment amounts

Amounts retain the source precision. Currency and monetary scale are not established; no currency symbol is assigned.

| Measure | Expected amount |
| --- | ---: |
| Total recorded payment amount, all statuses | 537276369.37 |
| Amount labeled `Paid` | 452200033.15 |
| Amount labeled `Late` | 58325978.83 |
| Amount labeled `Missed` | 26750357.39 |

```text
452200033.15 + 58325978.83 + 26750357.39 = 537276369.37
```

This arithmetic confirms consistency of the reported amounts; it does not authenticate database outputs, prove every amount is non-null, or prove that no other status rows exist. Other categories could have zero or offsetting amounts.

## 4. Definitions and counting rules

```text
coverage_exceeded_flag = 1 when claim_amount > coverage_amount; otherwise 0
processing_delay_flag = 1 when processing_days > 60; otherwise 0
risk_score             = 2 * coverage_exceeded_flag + processing_delay_flag
flagged claim          = coverage_exceeded_flag = 1 OR processing_delay_flag = 1
```

- Equality to coverage does not trigger a coverage flag. Exactly 60 days does not trigger a delay flag.
- The **60-day threshold and 2:1 weights are project review rules**. They are not a documented statutory deadline, contractual SLA, calibrated fraud model, or actuarial risk probability.
- Count **distinct claim IDs satisfying either rule** to obtain unique flagged claims. A claim satisfying both rules counts once. SQL row counts or binary-indicator sums equal distinct claims only after one row per non-null claim ID is established.
- **Do not use `SUM(risk_score)` as a flagged-claim count.** At the benchmark, the weighted score total would be `2 * 21 + 320 = 362`, while unique flagged claims are 341.
- Risk queries apply no claim-status or date filter. Pending and denied claims remain included. A coverage flag is a review signal, not proof of fraud, an incorrect payout, or a regulatory breach.

## 5. Repeatable validation workflow

The SQL blocks below are **supplemental rerun instructions**, not previously executed evidence or changes to the four source scripts. Run them in MySQL Workbench against the intended snapshot, and retain all outputs.

### Step 1 — Confirm environment and snapshot

Use an existing, populated `insurance_risk_analytics` database on MySQL 8.0+ as targeted by the scripts. Confirm `SELECT` access and `CREATE VIEW` permission when views need to be created. Record dataset identity, client/server versions, execution time, script revision, and configuration.

```sql
USE insurance_risk_analytics;
SELECT VERSION() AS mysql_version, DATABASE() AS schema_name,
       @@sql_mode AS sql_mode,
       @@character_set_database AS database_charset,
       @@collation_database AS database_collation;
```

Inspect actual table definitions, keys, constraints, nullability, and numeric precision using DQ01 and schema metadata. C03 retains nonaggregated detail columns with `GROUP BY claim_id`; compatibility depends on the actual enforced key and SQL mode. Do not change SQL mode merely to suppress a validation error.

### Step 2 — Run all data-quality checks

Execute `01_data_quality.sql` in full, including DQ06. Inspect every result set and the Workbench action output. Save duplicate/null/blank/category/amount/date/reference results separately; capture warnings immediately after the relevant statement with `SHOW WARNINGS;` when needed.

Distinguish zero issue counts from empty detail results, execution errors, and checks that were not run. Investigate findings and record any decisions or data changes before interpreting analytical outputs. The presence of a check in the script does not prove it passed.

Use this supplemental control to distinguish null IDs from repeated non-null IDs:

```sql
SELECT 'customers' AS source_name, COUNT(*) AS row_count,
       COUNT(*) - COUNT(customer_id) AS null_ids,
       COUNT(customer_id) - COUNT(DISTINCT customer_id) AS repeated_nonnull_id_rows
FROM customers
UNION ALL
SELECT 'policies', COUNT(*), COUNT(*) - COUNT(policy_id),
       COUNT(policy_id) - COUNT(DISTINCT policy_id) FROM policies
UNION ALL
SELECT 'claims', COUNT(*), COUNT(*) - COUNT(claim_id),
       COUNT(claim_id) - COUNT(DISTINCT claim_id) FROM claims
UNION ALL
SELECT 'payments', COUNT(*), COUNT(*) - COUNT(payment_id),
       COUNT(payment_id) - COUNT(DISTINCT payment_id) FROM payments;
```

Zero null/repeated key rows is the intended grain-control outcome, not a newly confirmed result. `COUNT(*) - COUNT(DISTINCT id)` combines null-ID rows and repeated non-null occurrences; it is not a pure duplicate count.

### Step 3 — Create or inspect views and reconcile populations

Run `02_cleaned_views.sql` only where the relevant view names are available. It creates schema objects without editing base-table rows. If views already exist, inspect and compare their definitions with the script; do not automatically drop or overwrite them:

```sql
SHOW CREATE VIEW vw_customers_clean;
SHOW CREATE VIEW vw_policies_clean;
SHOW CREATE VIEW vw_claims_analysis;
SHOW CREATE VIEW vw_payments_clean;
```

Inspect each existing view independently; do not treat an existing-name error as proof that the rest of file 02 ran. Execute its applicable SELECT checks separately after definitions are confirmed.

```sql
SELECT 'vw_customers_clean' AS view_name, COUNT(*) AS row_count,
       COUNT(DISTINCT customer_id) AS distinct_ids,
       COUNT(*) - COUNT(customer_id) AS null_ids FROM vw_customers_clean
UNION ALL
SELECT 'vw_policies_clean', COUNT(*), COUNT(DISTINCT policy_id),
       COUNT(*) - COUNT(policy_id) FROM vw_policies_clean
UNION ALL
SELECT 'vw_claims_analysis', COUNT(*), COUNT(DISTINCT claim_id),
       COUNT(*) - COUNT(claim_id) FROM vw_claims_analysis
UNION ALL
SELECT 'vw_payments_clean', COUNT(*), COUNT(DISTINCT payment_id),
       COUNT(*) - COUNT(payment_id) FROM vw_payments_clean;
```

Customer, policy, and payment views preserve raw row counts by definition; they do not deduplicate. The claims view uses `claims INNER JOIN policies ON policy_id`: unmatched claims disappear and duplicate parent policy IDs multiply claim rows. Matching raw/view totals alone can conceal exclusions offset by multiplication. Establish parent uniqueness and inspect excluded claims separately:

```sql
SELECT COUNT(*) AS claims_without_matching_policy
FROM claims AS c
WHERE NOT EXISTS (
    SELECT 1 FROM policies AS p WHERE p.policy_id = c.policy_id
);
```

This count includes null claim policy references. Use DQ04/DQ05 to inspect customer-policy and policy-payment references too. A zero excluded-claims count is a control target, not a result established by this document.

### Step 4 — Run claims analysis and reconcile counts

Execute `03_claims_risk_analysis.sql`, retaining C01–C15 outputs and any errors/warnings. Compare raw and matched populations before applying the snapshot benchmarks. Use the following single-population cross-check:

```sql
SELECT
    COUNT(*) AS matched_claim_rows,
    COUNT(DISTINCT claim_id) AS distinct_matched_claims,
    SUM(coverage_exceeded_flag) AS coverage_flag_rows,
    SUM(processing_delay_flag) AS delay_flag_rows,
    SUM(CASE WHEN coverage_exceeded_flag = 1
                  AND processing_delay_flag = 1 THEN 1 ELSE 0 END) AS overlap_rows,
    SUM(CASE WHEN coverage_exceeded_flag = 1
                   OR processing_delay_flag = 1 THEN 1 ELSE 0 END) AS flagged_rows,
    COUNT(DISTINCT CASE WHEN coverage_exceeded_flag = 1
                             OR processing_delay_flag = 1 THEN claim_id END)
        AS distinct_flagged_claims,
    ROUND(
        COUNT(DISTINCT CASE WHEN coverage_exceeded_flag = 1
                                 OR processing_delay_flag = 1 THEN claim_id END)
        * 100.0 / NULLIF(COUNT(DISTINCT claim_id), 0), 2
    ) AS distinct_matched_flagged_percentage
FROM vw_claims_analysis;
```

For a fully reconciled benchmark population, row and distinct counts should agree at 25,000, flags should be 21/320, overlap 0, unique flagged 341, and the displayed percentage 1.36%. A distinct count alone can hide a multiplying join; check all controls together.

**Denominators:** C02 divides matched coverage exceptions by **all raw claims**. C03 inspects raw delayed claims; C04 and view summaries use matched claims. C01 status percentages use all raw claims. C08/C09 and policy-type summaries use their matched populations. The supplemental percentage above uses distinct matched IDs. These measures are equivalent only after population/grain controls establish that equivalence. Record raw and matched denominators separately; do not force them to agree by changing filters.

Obtain claim-status and score distributions from C01/C06/C08. Reconcile their totals to the relevant population, retaining other/null categories rather than assuming the named statuses exhaust the data.

### Step 5 — Run payment analysis and reconcile amounts

Execute `04_payment_performance.sql`, saving P01 status/method distributions, P02 view counts/amounts, and P03 conditional status amounts. P02 and P03 totals should agree for the same snapshot. P03 uses:

```sql
SELECT
    COUNT(*) AS total_payments,
    SUM(payment_amount) AS total_recorded_amount,
    SUM(CASE WHEN payment_status = 'Paid' THEN payment_amount ELSE 0 END)
        AS paid_status_amount,
    SUM(CASE WHEN payment_status = 'Late' THEN payment_amount ELSE 0 END)
        AS late_status_amount,
    SUM(CASE WHEN payment_status = 'Missed' THEN payment_amount ELSE 0 END)
        AS missed_status_amount
FROM vw_payments_clean;
```

Compare with 80,000 rows and the exact amounts in section 3. Also inspect all categories and their amounts:

```sql
SELECT payment_status, COUNT(*) AS payment_rows,
       COUNT(*) - COUNT(payment_amount) AS null_amount_rows,
       SUM(payment_amount) AS recorded_amount
FROM vw_payments_clean
GROUP BY payment_status
ORDER BY payment_status;
```

Investigate any difference between total and the three named status sums. Inspect actual text values and collation; category comparisons can behave differently from Power BI. Compare amounts at source precision before rounding for presentation.

### Step 6 — Cross-check Power BI measures

Open the portfolio `.pbix` in Power BI Desktop. Confirm its actual imported table names, source settings, relationships, measure definitions, refresh state, and report/page/visual filters. The formulas below are **reference definitions**, not a verbatim extraction of the saved report's DAX.

```dax
Total Matched Claims (Reference) =
DISTINCTCOUNT ( 'vw_claims_analysis'[claim_id] )

Flagged Claims (Unique, Reference) =
CALCULATE (
    DISTINCTCOUNT ( 'vw_claims_analysis'[claim_id] ),
    KEEPFILTERS (
        'vw_claims_analysis'[coverage_exceeded_flag] = 1
            || 'vw_claims_analysis'[processing_delay_flag] = 1
    )
)

Flagged Claim Rate (Reference) =
DIVIDE ( [Flagged Claims (Unique, Reference)], [Total Matched Claims (Reference)] )
```

Format the rate as a percentage with two decimals; do not multiply this DAX ratio by 100 and then apply percentage formatting. These definitions assume validated non-null IDs: DAX `DISTINCTCOUNT` can count a blank while SQL `COUNT(DISTINCT ...)` excludes nulls.

| Power BI comparison | SQL control | Expected snapshot value |
| --- | --- | ---: |
| Raw customer/policy/claim/payment counts | DQ02, each corresponding raw table | 10000 / 18000 / 25000 / 80000 |
| Matched claim count | View row and distinct-ID controls | 25000 only after join/grain reconciliation |
| Coverage exceptions | Distinct matched IDs with coverage flag = 1 | 21 |
| Delayed claims | Distinct matched IDs with delay flag = 1 | 320 |
| Both flags | Distinct matched IDs with both flags = 1 | 0 |
| Unique flagged claims | Distinct matched IDs with either flag = 1 | 341 |
| Flagged rate | Same matched numerator and denominator | 1.36% displayed |
| Total recorded payment amount | `SUM(payment_amount)` across all statuses | 537276369.37 |
| Paid / Late / Missed amounts | Conditional sums using the same labels as P03 | 452200033.15 / 58325978.83 / 26750357.39 |

A payment reference measure is `SUM('vw_payments_clean'[payment_amount])`; status measures filter that same table to the relevant source label. Inspect actual model filters and category values before declaring equivalence. Counts and sums must use the same population, grain, date scope, and status treatment as SQL. For the full snapshot, clear or document slicers and all other filtering. Then test equivalent filtered comparisons if reporting segmented results.

The owner previously confirmed SQL-to-Power BI reconciliation of the core claims indicators. The later report that expected SQL outputs matched does not, by itself, establish that every Power BI payment measure or filter interaction was tested. No new dashboard reconciliation is claimed here.

**Refresh requires the existing MySQL source:** the server must be running and reachable, with the matching populated schema/views, credentials, permissions, and compatible Power BI MySQL connection support. Update local connection settings as needed, refresh, and retain refresh time/errors and comparison outputs. A saved report or GitHub checkout does not recreate the database. Displayed saved values do not prove a successful fresh refresh.

### Step 7 — Preserve a validation record

Save the dataset/schema identifier, script revision, MySQL/Workbench/Power BI versions, SQL mode/collation, execution and refresh timestamps, all relevant result exports, warnings/errors, and a comparison table of SQL versus Power BI values. Record each control as matched, finding, error, or not run. Document any corrective changes and rerun affected controls before accepting the new snapshot. Do not premark future checks as passed.

## 6. Known limitations and interpretation

- **NULL and CASE behavior:** Unknown comparisons fall through `ELSE 0` in the risk flags. A zero score does not prove complete inputs or absence of other risks. Nonpositive-value and date-order checks do not detect nulls automatically; DQ06 closes selected gaps, not every possible data-quality condition.
- **Original bucket edge cases:** Processing-time CASE sends null durations to `Over 90 days` and negative values to `0–15 days`. Ratio CASE sends null ratios to `>100%` and negative ratios to `0–25%`. Resolve invalid inputs or separately document revised buckets before interpretation; the original scripts retain these definitions.
- **Ratios and aggregates:** Coverage must be positive and non-null, with valid comparable claim amounts. The source ratio uses direct division without `NULLIF`; runtime warnings/errors must be inspected. `SUM`/`AVG` ignore null inputs, and `SUM` over an empty set can return null. The supplemental denominator guard above does not repair invalid source ratios. Average claim-level coverage ratios are not ratios of totals or premium-based loss ratios; average joined coverage is weighted by claim frequency.
- **Join and cleaning scope:** Inner joins can omit claims; duplicate parent keys can inflate them. Left-join profiling counts also assume unique parent keys. Customer cleaning only trims/nullifies gender and normalizes membership casing; blank membership remains blank. Policy/payment views are pass-throughs. No view certifies error-free data or performs deduplication.
- **Financial meaning:** Total recorded payments include all statuses. `Paid` is a source label, not independently verified collected cash. `Late` does not establish eventual receipt, and `Missed` does not establish actual arrears. Claim amounts are not verified payouts. Currency, conversion rules, and monetary scale are unspecified.
- **Missing payment semantics:** Due dates, billing periods/frequency, amounts due, reporting cutoff, and settlement/status rules are not supplied. On-time collection rates, overdue aging, and expected-versus-paid collections cannot be established from these scripts. Monthly trends and segment payment analysis are not included in the reviewed package.
- **Fact-table grain:** Do not directly join claim and payment detail by `policy_id` for combined totals; multiple records on both sides multiply rows. Aggregate each fact separately to the required reporting grain before combining.
- **Ranking and rounding:** Top-three queries return up to three rows per represented policy type, not a guaranteed 12. They use `ROW_NUMBER` with `claim_id` tie-breaking; ratio ranking precedes display rounding. Rounded category percentages may not total exactly 100%.
- **Coverage and duration assumptions:** The policy join does not establish coverage eligibility, benefit sublimits, or effective coverage at claim date. Calendar/business-day convention and processing event boundaries are not established from supplied workflow timestamps.
- **Synthetic dataset and reproducibility:** These results demonstrate portfolio methods, not actual insurer performance. The analytical package lacks complete database/table setup, data-generation/import scripts, and a reproducible seed. Exact end-to-end reproduction requires the matching existing MySQL database or an independently supplied matching schema/data snapshot.
- **Evidence scope:** Owner-reported expected outputs, static structural success, derived arithmetic, and future validation instructions remain separate. This document asserts neither independent database execution nor exhaustive QA, universal null/duplicate clearance, or proof of every report interaction.
