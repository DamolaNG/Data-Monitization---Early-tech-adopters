CREATE OR REPLACE VIEW early_tech_adopters AS
WITH rule1_purchase AS (
    -- Rule 1: purchased a SKU within 90 days of its launch.
    SELECT DISTINCT o.user_id
    FROM orders o
    JOIN product_catalog p ON p.sku = o.sku
    WHERE o.order_ts::date BETWEEN p.launch_date AND p.launch_date + 90
),
rule2_view AS (
    -- Rule 2: viewed the same SKU >= 2 times within 30 days of its launch.
    SELECT DISTINCT v.user_id
    FROM sku_views v
    JOIN product_catalog p ON p.sku = v.sku
    WHERE v.event_ts::date BETWEEN p.launch_date AND p.launch_date + 30
    GROUP BY v.user_id, v.sku
    HAVING COUNT(*) >= 2
),
rule3_profile AS (
    -- Rule 3: profile signal (supporting evidence only).
    SELECT DISTINCT user_id
    FROM profiles
    WHERE prefers_new_releases IS TRUE
       OR trade_in_member      IS TRUE
),
all_users AS (
    SELECT user_id FROM profiles
    UNION
    SELECT user_id FROM orders
    UNION
    SELECT user_id FROM sku_views
),
flags AS (
    SELECT
        u.user_id,
        (r1.user_id IS NOT NULL) AS r1_purchase,
        (r2.user_id IS NOT NULL) AS r2_view,
        (r3.user_id IS NOT NULL) AS r3_profile
    FROM all_users u
    LEFT JOIN rule1_purchase r1 USING (user_id)
    LEFT JOIN rule2_view     r2 USING (user_id)
    LEFT JOIN rule3_profile  r3 USING (user_id)
)
SELECT
    user_id,
    (r1_purchase OR r2_view) AS early_adopter_flag,
    NULLIF(
        ARRAY_TO_STRING(
            ARRAY_REMOVE(ARRAY[
                CASE WHEN r1_purchase                              THEN 'purchase' END,
                CASE WHEN r2_view                                  THEN 'view'     END,
                CASE WHEN r3_profile AND (r1_purchase OR r2_view)  THEN 'profile'  END
            ], NULL),
            ','
        ),
        ''
    ) AS evidence_source
FROM flags;



WITH active_users AS (
    SELECT DISTINCT user_id FROM orders
    WHERE order_ts >= CURRENT_DATE - INTERVAL '90 days'
    UNION
    SELECT DISTINCT user_id FROM sku_views
    WHERE event_ts >= CURRENT_DATE - INTERVAL '90 days'
)
SELECT
    (SELECT COUNT(*) FROM early_tech_adopters WHERE early_adopter_flag)        AS total_early_adopters,
    (SELECT COUNT(*) FROM active_users)                                        AS total_active_users,
    (SELECT COUNT(*) FROM early_tech_adopters s
        JOIN active_users a USING (user_id)
        WHERE s.early_adopter_flag)                                            AS active_early_adopters,
    ROUND(
        100.0 *
        (SELECT COUNT(*) FROM early_tech_adopters s
            JOIN active_users a USING (user_id)
            WHERE s.early_adopter_flag)
        / NULLIF((SELECT COUNT(*) FROM active_users), 0)
    , 2)                                                                       AS pct_active_users_flagged;



    SELECT
    evidence_source,
    COUNT(*) AS user_count
FROM early_tech_adopters
WHERE early_adopter_flag
GROUP BY evidence_source
ORDER BY user_count DESC;




WITH qualifying_events AS (
    -- Purchases inside the 90-day window
    SELECT DISTINCT o.user_id, p.category, 'purchase' AS rule_tag
    FROM orders o
    JOIN product_catalog p ON p.sku = o.sku
    WHERE o.order_ts::date BETWEEN p.launch_date AND p.launch_date + 90

    UNION ALL

    -- (user, SKU) view pairs with >=2 views inside the 30-day window
    SELECT v.user_id, p.category, 'view' AS rule_tag
    FROM sku_views v
    JOIN product_catalog p ON p.sku = v.sku
    WHERE v.event_ts::date BETWEEN p.launch_date AND p.launch_date + 30
    GROUP BY v.user_id, v.sku, p.category
    HAVING COUNT(*) >= 2
)
SELECT
    q.category,
    q.rule_tag,
    COUNT(DISTINCT q.user_id) AS distinct_flagged_users
FROM qualifying_events q
JOIN early_tech_adopters s
  ON s.user_id = q.user_id
 AND s.early_adopter_flag
GROUP BY q.category, q.rule_tag
ORDER BY q.category, q.rule_tag;