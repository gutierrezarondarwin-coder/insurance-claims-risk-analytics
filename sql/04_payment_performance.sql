-- Insurance Risk Analytics | Payment performance: recovered coverage
-- Dialect target: MySQL 8.0+ (CTEs and window functions in analysis).
-- Consolidated from the three supplied scripts on 2026-10-21.
-- STATIC REVIEW ONLY: no connection, execution, or result verification.
-- Prerequisite: existing insurance_risk_analytics schema and populated tables.
-- Requires vw_payments_clean from 02; status breakdowns use original raw payments table.
-- See VALIDATION_NOTES.md for known limitations and source coverage.

USE insurance_risk_analytics;

-- Grain: one recorded payment row, not necessarily one policy or billing period.
-- Paid/Late/Missed are source status labels; amounts are recorded amounts.
-- No due date, amount due, frequency or settlement mapping was supplied.
-- Consequently these are NOT verified collections, arrears, or timeliness KPIs.

-- P01. Payment status percentage and method counts
-- Source: 1_1.sql, lines 510-528.
-- Counts use raw records; no deduplication or payment-status filtering.
SELECT
    payment_status,
    COUNT(*) AS payment_count,
    ROUND(
        COUNT(*) * 100.0 /
        (SELECT COUNT(*) FROM payments),
        2
    ) AS payment_percentage

FROM payments
GROUP BY payment_status
ORDER BY payment_count DESC;

SELECT
    payment_method,
    COUNT(*) AS payment_count
FROM payments
GROUP BY payment_method
ORDER BY payment_count DESC;

-- P02. Payment view reconciliation
-- Source: 1_1.sql, lines 667-672.
-- SUM includes all statuses. It is total recorded amount, not confirmed cash received.
SELECT
    COUNT(*) AS total_payments,
    COUNT(DISTINCT payment_id) AS unique_payment_ids,
    COUNT(DISTINCT policy_id) AS policies_with_payments,
    SUM(payment_amount) AS total_recorded_payment_amount
FROM vw_payments_clean;

-- P03. Recorded amounts by source status
-- Source: 1_1.sql, lines 685-691.
-- Paid + Late + Missed may not equal total if there are other/null statuses.
SELECT
    COUNT(*) AS total_payments,
    SUM(payment_amount) AS total_recorded_amount,
    SUM(CASE WHEN payment_status = 'Paid' THEN payment_amount ELSE 0 END) AS paid_status_amount,
    SUM(CASE WHEN payment_status = 'Late' THEN payment_amount ELSE 0 END) AS late_status_amount,
    SUM(CASE WHEN payment_status = 'Missed' THEN payment_amount ELSE 0 END) AS missed_status_amount
FROM vw_payments_clean;

-- MISSING FROM THE THREE UPLOADS (not fabricated here):
-- 1. Monthly payment counts/amounts and status trends.
-- 2. Payment outcomes by policy type, region or membership.
-- 3. Policy-level payment/premium reconciliation and unpaid-policy coverage.
-- 4. On-time rate, overdue days/aging, expected-vs-paid collection rate.
-- Items 1-2 could be authored later from supplied columns with agreed meanings.
-- Items 3-4 require billing frequency, due dates, amount-due/settlement rules,
-- reporting cutoff and status definitions. premium_amount alone is insufficient.
-- Do not join claims directly to payments on policy_id: many-to-many rows can
-- inflate both amounts. Aggregate each fact to the intended grain first.
