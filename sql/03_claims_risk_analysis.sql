-- Insurance Risk Analytics | Claims risk analysis
-- Dialect target: MySQL 8.0+ (CTEs and window functions in analysis).
-- Consolidated from the three supplied scripts on 2026-10-21.
-- STATIC REVIEW ONLY: no connection, execution, or result verification.
-- Prerequisite: existing insurance_risk_analytics schema and populated tables.
-- Requires 02_cleaned_views.sql; remaining raw-table queries preserve their source population.
-- See VALIDATION_NOTES.md for known limitations and source coverage.

USE insurance_risk_analytics;

-- Preserve original business logic: no claims status/date filter; one row per
-- matched claim when policy_id is unique. A flag is a review signal, not fraud.
-- NULL comparisons fall through CASE to 0. Resolve missing inputs before using
-- scores as complete risk evidence. Ratios require positive non-null coverage.

-- C01. Raw claim profile and status mix
-- Source: 1.sql, lines 272-291.
-- AVG ignores NULL values.
SELECT
    COUNT(*) AS total_claims,
    MIN(claim_amount) AS minimum_claim,
    MAX(claim_amount) AS maximum_claim,
    ROUND(AVG(claim_amount), 2) AS average_claim,
    MIN(processing_days) AS minimum_processing_days,
    MAX(processing_days) AS maximum_processing_days,
    ROUND(AVG(processing_days), 2) AS average_processing_days
FROM claims;

SELECT
    claim_status,
    COUNT(*) AS claim_count,
    ROUND(
        COUNT(*) * 100.0 / (SELECT COUNT(*) FROM claims),
        2
    ) AS percentage
FROM claims
GROUP BY claim_status
ORDER BY claim_count DESC;

-- C02. Coverage exceptions: detail, rate, excess amounts
-- Source: 1.sql, lines 293-340.
-- Rate denominator is ALL raw claims; numerator uses matched policies.
SELECT
    c.claim_id,
    c.policy_id,
    c.claim_amount,
    p.coverage_amount
FROM claims AS c
INNER JOIN policies AS p
    ON c.policy_id = p.policy_id
WHERE c.claim_amount > p.coverage_amount
ORDER BY c.claim_amount DESC;

SELECT
    COUNT(*) AS claims_exceeding_coverage,
    ROUND(
        COUNT(*) * 100.0 / (SELECT COUNT(*) FROM claims),
        2
    ) AS percentage_of_all_claims
FROM claims AS c
INNER JOIN policies AS p
    ON c.policy_id = p.policy_id
WHERE c.claim_amount > p.coverage_amount;

SELECT
    c.claim_id,
    c.policy_id,
    p.policy_type,
    c.claim_amount,
    p.coverage_amount,
    c.claim_amount - p.coverage_amount AS excess_amount,
    c.processing_days
FROM claims AS c
INNER JOIN policies AS p
    ON c.policy_id = p.policy_id
WHERE c.claim_amount > p.coverage_amount
ORDER BY excess_amount DESC;

SELECT
    COUNT(*) AS claims_exceeding_coverage,
    ROUND(SUM(c.claim_amount - p.coverage_amount), 2)
        AS total_excess_amount,
    ROUND(AVG(c.claim_amount - p.coverage_amount), 2)
        AS average_excess_amount,
    ROUND(MAX(c.claim_amount - p.coverage_amount), 2)
        AS maximum_excess_amount
FROM claims AS c
INNER JOIN policies AS p
    ON c.policy_id = p.policy_id
WHERE c.claim_amount > p.coverage_amount;

-- C03. Raw claims processed beyond 60 days
-- Source: 1.sql, lines 348-356.
-- Original GROUP BY claim_id retained; relies on enforced claim_id primary key.
SELECT
    claim_id,
    policy_id,
    claim_amount,
    processing_days
FROM claims
WHERE processing_days > 60
GROUP BY claim_id
ORDER BY processing_days DESC;

-- C04. Coverage/processing overlap
-- Source: 1.sql, lines 358-396.
-- Counts apply to matched claims, unlike C03 raw-table count.
SELECT
    c.claim_id,
    c.policy_id,
    c.claim_amount,
    p.coverage_amount,
    c.processing_days
FROM claims AS c
INNER JOIN policies AS p
    ON c.policy_id = p.policy_id
WHERE c.claim_amount > p.coverage_amount
AND c.processing_days > 60
ORDER BY c.processing_days DESC;

SELECT
    SUM(
        CASE
            WHEN c.claim_amount > p.coverage_amount
            THEN 1 ELSE 0
        END
    ) AS exceeds_coverage,

    SUM(
        CASE
            WHEN c.processing_days > 60
            THEN 1 ELSE 0
        END
    ) AS over_60_days,

    SUM(
        CASE
            WHEN c.claim_amount > p.coverage_amount
                 AND c.processing_days > 60
            THEN 1 ELSE 0
        END
    ) AS both_conditions

FROM claims AS c
INNER JOIN policies AS p
    ON c.policy_id = p.policy_id;

-- C05. Original processing-time distribution
-- Source: 1.sql, lines 404-419.
-- KNOWN LIMITATION: NULL enters Over 90 days; negative days enter 0-15. Use only after DQ04 passes.
SELECT
    CASE
        WHEN processing_days <= 15 THEN '01. 0-15 days'
        WHEN processing_days <= 30 THEN '02. 16-30 days'
        WHEN processing_days <= 60 THEN '03. 31-60 days'
        WHEN processing_days <= 90 THEN '04. 61-90 days'
        ELSE '05. Over 90 days'
    END AS processing_time_group,
    COUNT(*) AS claim_count,
    ROUND(
        COUNT(*) * 100.0 / (SELECT COUNT(*) FROM claims),
        2
    ) AS percentage
FROM claims
GROUP BY processing_time_group
ORDER BY processing_time_group;

-- C06. Claims analytical KPIs
-- Source: 1_1.sql, lines 674-683.
-- Status labels are source literals; inspect actual categories and collation.
SELECT
    COUNT(*) AS total_claims,
    SUM(claim_amount) AS total_claim_amount,
    SUM(coverage_exceeded_flag) AS coverage_exceptions,
    SUM(processing_delay_flag) AS delayed_claims,
    SUM(CASE WHEN risk_score > 0 THEN 1 ELSE 0 END) AS flagged_claims,
    SUM(CASE WHEN claim_status = 'Approved' THEN 1 ELSE 0 END) AS approved_claims,
    SUM(CASE WHEN claim_status = 'Denied' THEN 1 ELSE 0 END) AS denied_claims,
    SUM(CASE WHEN claim_status = 'Pending' THEN 1 ELSE 0 END) AS pending_claims
FROM vw_claims_analysis;

-- C07. View flag reconciliation
-- Source: 1_1.sql, lines 632-643.
SELECT
    COUNT(*) AS total_claims,
    SUM(coverage_exceeded_flag) AS coverage_exceptions,
    SUM(processing_delay_flag) AS delayed_claims,
    SUM(
        CASE
            WHEN coverage_exceeded_flag = 1
             AND processing_delay_flag = 1
            THEN 1 ELSE 0
        END
    ) AS both_flags
FROM vw_claims_analysis;

-- C08. Risk categories and distribution
-- Source: 1.sql, lines 520-559.
-- One canonical version retained from repeated CTE/derived-table variants.
WITH claim_risk AS (
    SELECT
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
        END AS risk_score

    FROM claims AS c
    INNER JOIN policies AS p
        ON c.policy_id = p.policy_id
)

SELECT
    risk_score,

    CASE
        WHEN risk_score = 0 THEN 'No Flag'
        WHEN risk_score = 1 THEN 'Processing Flag'
        WHEN risk_score = 2 THEN 'Coverage Flag'
        WHEN risk_score = 3 THEN 'Multiple Flags'
    END AS risk_category,

    COUNT(*) AS claim_count,

    ROUND(
        COUNT(*) * 100.0 /
        (SELECT COUNT(*) FROM claim_risk),
        2
    ) AS percentage

FROM claim_risk
GROUP BY risk_score
ORDER BY risk_score DESC;

-- C09. Flag rate by policy type
-- Source: 1_1.sql, lines 31-67.
-- OR counts a claim once even if both conditions are true.
WITH claim_flags AS (
    SELECT
        p.policy_type,

        CASE
            WHEN c.claim_amount > p.coverage_amount
                 OR c.processing_days > 60
            THEN 1
            ELSE 0
        END AS flagged

    FROM claims AS c
    INNER JOIN policies AS p
        ON c.policy_id = p.policy_id
),

policy_summary AS (
    SELECT
        policy_type,
        COUNT(*) AS total_claims,
        SUM(flagged) AS flagged_claims
    FROM claim_flags
    GROUP BY policy_type
)

SELECT
    policy_type,
    total_claims,
    flagged_claims,

    ROUND(
        flagged_claims * 100.0 / total_claims,
        2
    ) AS flag_rate_percentage

FROM policy_summary
ORDER BY flag_rate_percentage DESC;

-- C10. Separate policy-type exception counts
-- Source: 1_1.sql, lines 548-586.
WITH claim_flags AS (
    SELECT
        p.policy_type,

        CASE
            WHEN c.claim_amount > p.coverage_amount
            THEN 1
            ELSE 0
        END AS coverage_flags,

        CASE
            WHEN c.processing_days > 60
            THEN 1
            ELSE 0
        END AS processing_flags,

        CASE
            WHEN c.claim_amount > p.coverage_amount
                 OR c.processing_days > 60
            THEN 1
            ELSE 0
        END AS total_flagged


    FROM claims AS c
    INNER JOIN policies AS p
        ON c.policy_id = p.policy_id
)

SELECT
    policy_type,
    COUNT(*) AS total_claims,
    SUM(coverage_flags) AS coverage_flags,
    SUM(processing_flags) AS processing_flags,
    SUM(total_flagged) AS total_flagged

FROM claim_flags
GROUP BY policy_type
ORDER BY total_flagged DESC;

-- C11. Claim-to-coverage ratios by policy type
-- Source: 1_1.sql, lines 69-94.
-- Average of claim-level ratios; not ratio of totals. Coverage average is claim-weighted.
SELECT
    p.policy_type,
    COUNT(*) AS total_claims,

    ROUND(AVG(p.coverage_amount), 2)
        AS avg_coverage_amount,

    ROUND(AVG(c.claim_amount), 2)
        AS avg_claim_amount,

    ROUND(
        AVG(c.claim_amount / p.coverage_amount) * 100,
        2
    ) AS avg_claim_to_coverage_pct,

    ROUND(
        MAX(c.claim_amount / p.coverage_amount) * 100,
        2
    ) AS max_claim_to_coverage_pct

FROM claims AS c
INNER JOIN policies AS p
    ON c.policy_id = p.policy_id

GROUP BY p.policy_type
ORDER BY avg_claim_to_coverage_pct DESC;

-- C12. Original ratio bands by policy type
-- Source: 1_1.sql, lines 96-129.
-- KNOWN LIMITATION: NULL ratio enters >100%; negative ratio enters 0-25%. Require valid amounts/coverage.
WITH claim_ratios AS (
    SELECT
        p.policy_type,
        c.claim_amount / p.coverage_amount * 100 AS claim_coverage_pct

    FROM claims AS c
    INNER JOIN policies AS p
        ON c.policy_id = p.policy_id
)

SELECT
    policy_type,

    CASE
        WHEN claim_coverage_pct <= 25 THEN '01. 0-25%'
        WHEN claim_coverage_pct <= 50 THEN '02. >25-50%'
        WHEN claim_coverage_pct <= 75 THEN '03. >50-75%'
        WHEN claim_coverage_pct <= 100 THEN '04. >75-100%'
        ELSE '05. >100%'
    END AS claim_coverage_group,

    COUNT(*) AS claim_count,

    ROUND(
        COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER (
            PARTITION BY policy_type
        ),
        2
) AS pct_of_policy_claims

FROM claim_ratios
GROUP BY policy_type, claim_coverage_group
ORDER BY policy_type, claim_coverage_group;

-- C13. Top three claim amounts per policy type
-- Source: 1_1.sql, lines 131-157.
-- ROW_NUMBER uses claim_id as tie-breaker; returns up to 3 per represented type.
WITH ranked_claims AS (
    SELECT
        c.claim_id,
        p.policy_type,
        c.claim_amount,
        p.coverage_amount,

        ROW_NUMBER() OVER (
            PARTITION BY p.policy_type
            ORDER BY c.claim_amount DESC, c.claim_id
        ) AS claim_rank

    FROM claims AS c
    INNER JOIN policies AS p
        ON c.policy_id = p.policy_id
)

SELECT
    claim_id,
    policy_type,
    claim_amount,
    coverage_amount,
    claim_rank

FROM ranked_claims
WHERE claim_rank <= 3
ORDER BY policy_type, claim_rank;

-- C14. Top three claim-to-coverage ratios per policy type
-- Source: 1_1.sql, lines 159-200.
-- Rank before display rounding; preserve both CTEs and claim_id tie-breaker. No fixed 12-row claim.
WITH claim_ratios AS (

    SELECT
        c.claim_id,
        p.policy_type,
        c.claim_amount,
        p.coverage_amount,
        c.claim_amount / p.coverage_amount * 100
            AS claim_coverage_pct

    FROM claims AS c
    INNER JOIN policies AS p
        ON c.policy_id = p.policy_id
),

ranked_claims AS (
    SELECT
        claim_id,
        policy_type,
        claim_amount,
        coverage_amount,
        claim_coverage_pct,

        ROW_NUMBER() OVER (
            PARTITION BY policy_type
            ORDER BY claim_coverage_pct DESC, claim_id
        ) AS ratio_rank

    FROM claim_ratios
)

SELECT
    claim_id,
    policy_type,
    claim_amount,
    coverage_amount,
    ROUND (claim_coverage_pct, 2) AS claim_coverage_pct,
    ratio_rank

FROM ranked_claims
WHERE ratio_rank <= 3
ORDER BY policy_type, ratio_rank;

-- C15. Review queue, equivalent to original 1.sql lines 421-467, using V03.
-- Reuses the original flags/score; no new thresholds or status exclusions.
SELECT claim_id, policy_id, policy_type, claim_amount, coverage_amount,
       processing_days, coverage_exceeded_flag, processing_delay_flag, risk_score
FROM vw_claims_analysis
ORDER BY risk_score DESC;
