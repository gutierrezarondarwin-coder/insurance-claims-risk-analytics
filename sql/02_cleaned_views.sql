-- Insurance Risk Analytics | Cleaned and analytical views
-- Dialect target: MySQL 8.0+ (CTEs and window functions in analysis).
-- Consolidated from the three supplied scripts on 2026-10-21.
-- STATIC REVIEW ONLY: no connection, execution, or result verification.
-- Prerequisite: existing insurance_risk_analytics schema and populated tables.
-- Run after 01; run 03 and 04 after these view definitions exist.
-- See VALIDATION_NOTES.md for known limitations and source coverage.

USE insurance_risk_analytics;

-- CREATE VIEW deliberately replaces source CREATE OR REPLACE VIEW.
-- Existing views cause an error rather than being overwritten. Review existing
-- definitions separately; this file does not alter or remove existing objects.
-- This is schema DDL, not a read-only script; base-table records stay unchanged.

-- V01. Customer normalization
-- Source: 1_1.sql, lines 268-286.
-- Only gender blanks/whitespace and membership casing are transformed; not deduplication.
CREATE VIEW vw_customers_clean AS
SELECT
    customer_id,
    join_date,
    birth_date,

    NULLIF(TRIM(gender), '') AS gender,

    region,
    province,

    CONCAT(
        UPPER(LEFT(TRIM(membership_type),1)),
        LOWER(SUBSTRING(TRIM(membership_type),2))
    ) AS membership_type,

    customer_status

FROM customers;

-- V02. Policy pass-through view
-- Source: 1_1.sql, lines 530-540.
-- No filtering, imputation, or normalization; clean is the original name only.
CREATE VIEW vw_policies_clean AS
SELECT
    policy_id,
    customer_id,
    policy_type,
    coverage_amount,
    premium_amount,
    start_date,
    end_date,
    policy_status
FROM policies;

-- V03. Claims analytical view
-- Source: 1_1.sql, lines 588-630.
-- Original INNER JOIN and score retained: coverage exceeded=2; processing_days >60=1.
CREATE VIEW vw_claims_analysis AS
SELECT
    c.claim_id,
    c.policy_id,
    p.policy_type,
    c.claim_date,
    c.claim_type,
    c.claim_amount,
    p.coverage_amount,
    c.claim_status,
    c.processing_days,

    CASE
        WHEN c.claim_amount > p.coverage_amount
        THEN 1
        ELSE 0
    END AS coverage_exceeded_flag,

    CASE
        WHEN c.processing_days > 60
        THEN 1
        ELSE 0
    END AS processing_delay_flag,

    c.claim_amount / p.coverage_amount * 100 AS claim_coverage_pct,

    (
        CASE
            WHEN c.claim_amount > p.coverage_amount
            THEN 2
            ELSE 0
            END
        +
        CASE
            WHEN c.processing_days > 60
            THEN 1
            ELSE 0
            END
    ) AS risk_score

FROM claims AS c
INNER JOIN policies AS p
    ON c.policy_id = p.policy_id;

-- V04. Payment pass-through view
-- Source: 1_1.sql, lines 657-665.
-- No status/amount changes; this is not evidence of successful collection.
CREATE VIEW vw_payments_clean AS
SELECT
    payment_id,
    policy_id,
    payment_date,
    payment_amount,
    payment_status,
    payment_method
FROM payments;

-- V05. Customer view checks
-- Source: 1_1.sql, lines 291-315.
-- COUNT(*) - COUNT(DISTINCT id) includes null IDs; use DQ06 to distinguish them.
SELECT
    COUNT(*) AS total_customers,

    SUM(
        CASE WHEN gender IS NULL THEN 1 ELSE 0 END
    ) AS null_gender,

    SUM(
        CASE WHEN TRIM(gender) = '' THEN 1 ELSE 0 END
    ) AS blank_gender

FROM vw_customers_clean;

SELECT
    membership_type,
    COUNT(*) AS customer_count
FROM vw_customers_clean
GROUP BY membership_type
ORDER BY membership_type;

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT customer_id) AS unique_customer_ids,
    COUNT(*) - COUNT(DISTINCT customer_id) AS duplicate_customer_ids
FROM vw_customers_clean;

-- V06. Policy view checks
-- Source: 1_1.sql, lines 542-546.
SELECT
    COUNT(*) AS total_policies,
    COUNT(DISTINCT policy_id) AS unique_policy_ids,
    COUNT(DISTINCT customer_id) AS customers_with_policies
FROM vw_policies_clean;

-- V07. View row counts
-- Source: 1_1.sql, lines 693-697.
-- Claims view may exclude unmatched policies; compare with DQ04, not just raw total.
SELECT
    (SELECT COUNT(*) FROM vw_customers_clean) AS customers,
    (SELECT COUNT(*) FROM vw_policies_clean) AS policies,
    (SELECT COUNT(*) FROM vw_claims_analysis) AS claims,
    (SELECT COUNT(*) FROM vw_payments_clean) AS payments;
