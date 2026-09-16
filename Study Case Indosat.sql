-- =============================================================================
-- Description : Monthly Insurance Revenue Recapitulation Report
-- Purpose     : Calculate total revenue and unique buyer count per month
-- Source Table: 
-- =============================================================================

SELECT
  -- Format transaction date (dt_id) into year-month format (YYYY-MM)
  TO_CHAR(dt_id, 'YYYY-MM') AS transaction_month,
  
  -- Calculate total revenue from insurance transactions for that month
  SUM(insurance_revenue) AS total_insurance_revenue,
  
  -- Count unique buyers (msisdn) to avoid duplicate counting
  COUNT(DISTINCT msisdn) AS total_buyers

FROM
  'data-fintech-prd-do1t.dm_external.sample_insurance_transaction_daily'

-- Group data by transaction month expression
GROUP BY
  TO_CHAR(dt_id, 'YYYY-MM')

-- Sort report results chronologically from oldest to newest month
ORDER BY
  transaction_month ASC;



-- =============================================================================
-- Description : Insurance Revenue Performance Report per Brand
-- Purpose     : Calculate total revenue and unique buyer count by brand
-- Sources     :  (Table 1) &  (Table 2)
-- Relation    : INNER JOIN via msisdn column (Phone Number)
-- =============================================================================

SELECT
  -- Brand name registered in the whitelist table
  w.brand_name,
  
  -- Calculate cumulative insurance revenue per brand.
  -- COALESCE is used to replace NULL values with 0 for safe calculation.
  SUM(COALESCE(t.insurance_revenue, 0)) AS total_insurance_revenue,
  
  -- Count unique users/buyers (msisdn) who made transactions
  COUNT(DISTINCT t.msisdn) AS total_buyers

FROM
  'data-fintech-prd-do1t.dm_external.sample__daily' AS w

-- Join whitelist data with transactions.
-- INNER JOIN only retrieves msisdns registered in whitelist AND have transacted.
INNER JOIN
  'data-fintech-prd-do1t.dm_external.sample__daily' AS t
  ON w.msisdn = t.msisdn

-- Group aggregation results by brand name
GROUP BY
  w.brand_name

-- Sort results from highest to lowest revenue
ORDER BY
  total_insurance_revenue DESC;



-- =============================================================================
-- Description : Customer Segmentation (User Lifecycle / RFM Analysis) - Last 90 Days
-- Purpose     : Classify whitelisted users into transaction behavior segments:
--               - Never Taker, New Buyer, Repeat Buyer, Lapsing Buyer, Lapsed Buyer
-- Sources      :  & 
-- =============================================================================

WITH whitelist_recent AS (
  -- CTE 1: Filter users whitelisted within the last 90 days.
  -- Uses GROUP BY msisdn to ensure 1 unique msisdn (prevents duplication 
  -- if a user has multiple brand_names in the whitelist table).
  SELECT
    msisdn,
    MAX(brand_name) AS brand_name -- Take the latest/top brand_name if duplicates exist
  FROM 'data-fintech-prd-do1t.dm_external.sample__daily'
  WHERE dt_id >= CURRENT_DATE - INTERVAL '90 days'
  GROUP BY msisdn
),

txn_recent AS (
  -- CTE 2: Aggregate last 90 days transactions per msisdn.
  -- Calculates Recency (last transaction date), Frequency (txn count), and Monetary metrics.
  SELECT
    msisdn,
    COUNT(DISTINCT transaction_id) AS txn_count_90d,
    MAX(dt_id) AS last_txn_date,
    SUM(COALESCE(insurance_revenue, 0)) AS total_insurance_revenue_90d
  FROM 'data-fintech-prd-do1t.dm_external.sample__daily'
  WHERE dt_id >= CURRENT_DATE - INTERVAL '90 days'
  GROUP BY msisdn
),

merged AS (
  -- CTE 3: Combine whitelist data with transaction statistics.
  -- Uses LEFT JOIN so whitelisted users who never transacted are still retained.
  SELECT
    w.msisdn,
    w.brand_name,
    COALESCE(t.txn_count_90d, 0) AS txn_count_90d,
    t.last_txn_date,
    COALESCE(t.total_insurance_revenue_90d, 0) AS total_insurance_revenue_90d,
    
    -- Calculate days difference between today and the last transaction date (Recency)
    (CURRENT_DATE - t.last_txn_date) AS days_since_last_txn
  FROM whitelist_recent w
  LEFT JOIN txn_recent t
    ON w.msisdn = t.msisdn
)

-- MAIN QUERY: Determine lifecycle segment based on Recency & Frequency
SELECT
  msisdn,
  brand_name,
  txn_count_90d,
  last_txn_date,
  days_since_last_txn,
  total_insurance_revenue_90d,
  
  CASE
    -- Segment 1: Whitelisted but never transacted in the last 90 days
    WHEN txn_count_90d = 0 OR last_txn_date IS NULL THEN 'Never Taker'

    -- Segment 2: Only 1 transaction & transaction is still recent (<= 30 days)
    WHEN txn_count_90d = 1 
         AND days_since_last_txn <= 30 THEN 'New Buyer'

    -- Segment 3: 2 or more transactions & still active (<= 30 days)
    WHEN txn_count_90d >= 2 
         AND days_since_last_txn <= 30 THEN 'Repeat Buyer'

    -- Segment 4: Transacted before, but becoming inactive (31 - 60 days since last txn)
    WHEN days_since_last_txn BETWEEN 31 AND 60 THEN 'Lapsing Buyer'

    -- Segment 5: Transacted before, but inactive for a longer period (61 - 90 days)
    WHEN days_since_last_txn BETWEEN 61 AND 90 THEN 'Lapsed Buyer'

    ELSE 'Other'
  END AS lifecycle_segment

FROM merged
ORDER BY
  lifecycle_segment ASC,
  days_since_last_txn ASC NULLS LAST;
