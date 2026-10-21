-- Insurance Risk Analytics | Data quality assessment
-- Dialect target: MySQL 8.0+ (CTEs and window functions in analysis).
-- Consolidated from the three supplied scripts on 2026-10-21.
-- STATIC REVIEW ONLY: no connection, execution, or result verification.
-- Prerequisite: existing insurance_risk_analytics schema and populated tables.
-- Read-only checks; run before views and analysis.
-- See VALIDATION_NOTES.md for known limitations and source coverage.

USE insurance_risk_analytics;

-- DQ01. Inspect actual column definitions
-- Source: 1.sql, lines 188-196.
SELECT
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE,
    COLUMN_KEY
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = 'insurance_risk_analytics'
ORDER BY TABLE_NAME, ORDINAL_POSITION;

-- DQ02. Counts, duplicate keys, missing values, categories and region distribution
-- Source: 01_data_quality.sql, lines 13-186.
-- Counts have no supplied control totals. Duplicate checks do not prove keys are non-null.
SELECT 'customers' AS table_name, COUNT(*) AS row_count
FROM customers

UNION ALL

SELECT 'policies', COUNT(*)
FROM policies

UNION ALL

SELECT 'claims', COUNT(*)
FROM claims

UNION ALL

SELECT 'payments', COUNT(*)
FROM payments;

-- ------------------------------------------------------------
-- 2. DUPLICATE PRIMARY KEY CHECK
-- ------------------------------------------------------------

SELECT
    customer_id,
    COUNT(*) AS occurrence_count
FROM customers
GROUP BY customer_id
HAVING COUNT(*) > 1;

SELECT
    policy_id,
    COUNT(*) AS occurrence_count
FROM policies
GROUP BY policy_id
HAVING COUNT(*) > 1;

SELECT
    claim_id,
    COUNT(*) AS occurrence_count
FROM claims
GROUP BY claim_id
HAVING COUNT(*) > 1;

SELECT
    payment_id,
    COUNT(*) AS occurrence_count
FROM payments
GROUP BY payment_id
HAVING COUNT(*) > 1;

-- ------------------------------------------------------------
-- 3. MISSING VALUE CHECK
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS total_records,

    SUM(
        CASE
            WHEN gender IS NULL OR TRIM(gender) = ''
            THEN 1
            ELSE 0
        END
    ) AS missing_gender,

    SUM(
        CASE
            WHEN region IS NULL OR TRIM(region) = ''
            THEN 1
            ELSE 0
        END
    ) AS missing_region,

    SUM(
        CASE
            WHEN province IS NULL OR TRIM(province) = ''
            THEN 1
            ELSE 0
        END
    ) AS missing_province,

    SUM(
        CASE
            WHEN membership_type IS NULL
                 OR TRIM(membership_type) = ''
            THEN 1
            ELSE 0
        END
    ) AS missing_membership_type

FROM customers;

-- ------------------------------------------------------------
-- 4. CATEGORICAL VALUE CHECKS
-- ------------------------------------------------------------

SELECT
    gender,
    COUNT(*) AS record_count
FROM customers
GROUP BY gender
ORDER BY record_count DESC;


SELECT
    membership_type,
    BINARY membership_type AS exact_value,
    COUNT(*) AS record_count
FROM customers
GROUP BY
    membership_type,
    BINARY membership_type
ORDER BY membership_type;


SELECT
    customer_status,
    COUNT(*) AS record_count
FROM customers
GROUP BY customer_status
ORDER BY record_count DESC;


SELECT
    policy_type,
    COUNT(*) AS record_count
FROM policies
GROUP BY policy_type
ORDER BY record_count DESC;


SELECT
    policy_status,
    COUNT(*) AS record_count
FROM policies
GROUP BY policy_status
ORDER BY record_count DESC;


SELECT
    claim_status,
    COUNT(*) AS record_count
FROM claims
GROUP BY claim_status
ORDER BY record_count DESC;


SELECT
    payment_status,
    COUNT(*) AS record_count
FROM payments
GROUP BY payment_status
ORDER BY record_count DESC;


SELECT
    payment_method,
    COUNT(*) AS record_count
FROM payments
GROUP BY payment_method
ORDER BY record_count DESC;

-- Customer distribution by region

SELECT
    region,
    COUNT(*) AS customer_count,
    ROUND(
        COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customers),
        2
    ) AS percentage
FROM customers
GROUP BY region
ORDER BY customer_count DESC;

-- DQ03. Separate null and blank customer fields
-- Source: 1_1.sql, lines 202-233.
SELECT
    COUNT(*) AS total_customers,

    SUM(
        CASE
            WHEN gender IS NULL THEN 1
            ELSE 0
        END
    ) AS null_gender,

    SUM(
        CASE
            WHEN TRIM(gender) = '' THEN 1
            ELSE 0
        END
    ) AS blank_gender,

    SUM(
        CASE
            WHEN membership_type IS NULL THEN 1
            ELSE 0
        END
    ) AS null_membership,

    SUM(
        CASE
            WHEN TRIM(membership_type) = '' THEN 1
            ELSE 0
        END
    ) AS blank_membership

FROM customers;

-- DQ04. Policy and claim validity / reference checks
-- Source: 1_1.sql, lines 317-439.
-- Nonpositive-amount checks exclude NULL; LEFT JOIN counts assume unique parent IDs.
SELECT
    COUNT(*) AS total_policies,

    SUM(
        CASE
            WHEN policy_type IS NULL THEN 1
            ELSE 0
        END
    ) AS null_policy_type,

    SUM(
        CASE
            WHEN TRIM(policy_type) = '' THEN 1
            ELSE 0
        END
    ) AS blank_policy_type,

    SUM(
        CASE
            WHEN coverage_amount <= 0 THEN 1
            ELSE 0
        END
    ) AS invalid_coverage,

    SUM(
        CASE
            WHEN premium_amount <= 0 THEN 1
            ELSE 0
        END
    ) AS invalid_premium,

    SUM(
        CASE
            WHEN end_date < start_date THEN 1
            ELSE 0
        END
    ) AS invalid_dates

FROM policies;

SELECT
    COUNT(*) AS total_policies,
    COUNT(DISTINCT p.policy_id) AS unique_policy_ids,

    SUM(
        CASE
            WHEN c.customer_id IS NULL THEN 1
            ELSE 0
        END
    ) AS unmatched_customer_refs

FROM policies AS p
LEFT JOIN customers AS c
    ON p.customer_id = c.customer_id;

SELECT
    COUNT(*) AS total_claims,

    SUM(
        CASE
            WHEN claim_type IS NULL THEN 1
            ELSE 0
        END
    ) AS null_claim_type,

    SUM(
        CASE
            WHEN TRIM(claim_type) = '' THEN 1
            ELSE 0
        END
    ) AS blank_claim_type,

    SUM(
        CASE
            WHEN claim_status IS NULL THEN 1
            ELSE 0
        END
    ) AS null_claim_status,

    SUM(
        CASE
            WHEN TRIM(claim_status) = '' THEN 1
            ELSE 0
        END
    ) AS blank_claim_status,

    SUM(
        CASE
            WHEN claim_amount <= 0 THEN 1
            ELSE 0
        END
    ) AS invalid_claim_amount,

    SUM(
        CASE
            WHEN processing_days < 0 THEN 1
            ELSE 0
        END
    ) AS negative_processing_days,

    SUM(
        CASE
            WHEN processing_days IS NULL THEN 1
            ELSE 0
        END
    ) AS null_processing_days

FROM claims;

SELECT
    COUNT(*) AS total_claims,
    COUNT(DISTINCT c.claim_id) AS unique_claims_ids,

    SUM(
        CASE
            WHEN p.policy_id IS NULL THEN 1
            ELSE 0
        END
    ) AS unmatched_policy_refs

FROM claims AS c
LEFT JOIN policies AS p
    ON c.policy_id = p.policy_id;

-- DQ05. Payment validity / reference checks
-- Source: 1_1.sql, lines 448-508.
SELECT
    COUNT(*) AS total_payments,

    SUM(
        CASE
            WHEN payment_status IS NULL THEN 1
            ELSE 0
        END
    ) AS null_payment_status,

    SUM(
        CASE
            WHEN TRIM(payment_status) = '' THEN 1
            ELSE 0
        END
    ) AS blank_payment_status,

    SUM(
        CASE
            WHEN payment_method IS NULL THEN 1
            ELSE 0
        END
    ) AS null_payment_method,

    SUM(
        CASE
            WHEN TRIM(payment_method) = '' THEN 1
            ELSE 0
        END
    ) AS blank_payment_method,

    SUM(
        CASE
            WHEN payment_amount <= 0 THEN 1
            ELSE 0
        END
    ) AS invalid_payment_amount,

    SUM(
        CASE
            WHEN payment_date IS NULL THEN 1
            ELSE 0
        END
    ) AS null_payment_date

FROM payments;

SELECT
    COUNT(*) AS total_payments,
    COUNT(DISTINCT pay.payment_id) AS unique_payment_ids,

    SUM(
        CASE
            WHEN p.policy_id IS NULL THEN 1
            ELSE 0
        END
    ) AS unmatched_policy_refs

FROM payments AS pay
LEFT JOIN policies AS p
    ON pay.policy_id = p.policy_id;

-- DQ06. Additional review checks (NEW; not recovered source queries).
-- Close explicit NULL/key gaps without changing source analysis rules.
SELECT 'customers' AS table_name, COUNT(*) - COUNT(customer_id) AS null_ids FROM customers
UNION ALL
SELECT 'policies', COUNT(*) - COUNT(policy_id) FROM policies
UNION ALL
SELECT 'claims', COUNT(*) - COUNT(claim_id) FROM claims
UNION ALL
SELECT 'payments', COUNT(*) - COUNT(payment_id) FROM payments;

SELECT
    COUNT(*) - COUNT(coverage_amount) AS null_coverage,
    COUNT(*) - COUNT(premium_amount) AS null_premium,
    COUNT(*) - COUNT(start_date) AS null_start_date
FROM policies;

SELECT
    COUNT(*) - COUNT(claim_amount) AS null_claim_amount,
    COUNT(*) - COUNT(claim_date) AS null_claim_date
FROM claims;

SELECT COUNT(*) - COUNT(payment_amount) AS null_payment_amount
FROM payments;
