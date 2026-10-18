-- ---------------------------------------------------------------------------
-- MGIS 355 · Project 1 · Queries to audit
--
-- Four queries pulled from the shared analytics folder at Ridgeline. Each one
-- has been run, and each one has had its number quoted in a meeting.
--
-- Pick ONE for the "audited query" section of your verification log. Then:
--
--   1. Read the header and say, in your own words, what the query CLAIMS to
--      return. Do this before you read the SQL.
--   2. Run it against ridgeline.duckdb.
--   3. Work out what it ACTUALLY returns.
--   4. Name the failure: silent fan-out, a dimension join acting as a filter,
--      wrong grain, date logic, or a filter that quietly changes the answer.
--   5. Quantify the error. Produce the corrected number next to the wrong one
--      and state the difference in dollars, rows, or percentage points.
--
-- Every one of these queries runs without error and returns a plausible
-- number. Exactly one thing is wrong with each. "It looks fine" is a wrong
-- answer on all four.
--
-- Written against the raw extract, not against your star.
-- ---------------------------------------------------------------------------


-- ===========================================================================
-- QUERY A
-- Inherited from: the FY2026 promo review deck, slide 7
-- Claims to return: total promotional discount given, by district, for
--                   Q3 FY2026 to date. Used to argue the promo calendar is
--                   overspending in District 1.
-- ===========================================================================

SELECT s.district_id,
       ROUND(SUM(o.discount_amount), 2) AS promo_discount
FROM orders o
JOIN order_items i ON i.order_id = o.order_id
JOIN stores s      ON s.store_id = o.selling_store_id
WHERE o.order_status = 'completed'
  AND o.order_ts >= '2026-07-01'
  AND o.order_ts <  '2026-09-01'
GROUP BY s.district_id
ORDER BY s.district_id;


-- ===========================================================================
-- QUERY B
-- Inherited from: the weekly store scorecard, maintained by a predecessor
-- Claims to return: revenue by store for Jul-Aug 2026. The note on the
--                   scorecard says "rows sum to company revenue for the
--                   period."
-- ===========================================================================

SELECT s.store_code,
       s.store_name,
       ROUND(SUM(i.quantity * i.unit_price - i.line_discount), 2) AS revenue,
       COUNT(*) AS lines
FROM orders o
JOIN order_items i ON i.order_id = o.order_id
JOIN stores s      ON s.store_id = o.selling_store_id
WHERE o.order_status = 'completed'
  AND o.order_ts >= '2026-07-01'
  AND o.order_ts <  '2026-09-01'
GROUP BY s.store_code, s.store_name
ORDER BY revenue DESC;


-- ===========================================================================
-- QUERY C
-- Inherited from: a Monday-morning email that goes to the Burlington store
--                 manager every week
-- Claims to return: Burlington's revenue by week, so the manager can see
--                   which weeks were strong. Week 31 is the number in
--                   dispute -- the manager says it is too low.
-- ===========================================================================

SELECT WEEK(o.order_ts::DATE) AS iso_week,
       ROUND(SUM(i.quantity * i.unit_price - i.line_discount), 2) AS revenue
FROM orders o
JOIN order_items i ON i.order_id = o.order_id
JOIN stores s      ON s.store_id = o.selling_store_id
WHERE o.order_status = 'completed'
  AND s.store_code = 'BUR'
  AND o.order_ts >= '2026-07-01'
  AND o.order_ts <  '2026-09-01'
GROUP BY iso_week
ORDER BY iso_week;


-- ===========================================================================
-- QUERY D
-- Inherited from: the merchandising team's Q3 category review
-- Claims to return: Burlington footwear revenue this year against last year,
--                   with the year-over-year change. The -59.6% in this output
--                   is the number that started the conversation about closing
--                   the footwear wall at Burlington.
-- ===========================================================================

WITH yr AS (
    SELECT CASE WHEN o.order_ts < '2026-01-01' THEN 2025 ELSE 2026 END AS fy,
           SUM(i.quantity * i.unit_price - i.line_discount) AS revenue
    FROM orders o
    JOIN order_items i ON i.order_id = o.order_id
    JOIN stores s      ON s.store_id = o.selling_store_id
    JOIN products p    ON p.product_id = i.product_id
    WHERE o.order_status = 'completed'
      AND s.store_code = 'BUR'
      AND p.department = 'Footwear'
    GROUP BY fy
)
SELECT ROUND(MAX(CASE WHEN fy = 2025 THEN revenue END), 2) AS fy2025,
       ROUND(MAX(CASE WHEN fy = 2026 THEN revenue END), 2) AS fy2026,
       ROUND(100.0 * (MAX(CASE WHEN fy = 2026 THEN revenue END)
                    / MAX(CASE WHEN fy = 2025 THEN revenue END) - 1), 1) AS pct_change
FROM yr;
