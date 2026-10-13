-- Demo script that the CI workflow runs and captures output.
-- Shows RLS behavior and function behavior for two tenants.
-- The workflow will include the commit SHA and metadata separately.

-- Print a header
SELECT '--- DEMO START ---' AS note;
SELECT now() AS run_at, inet_server_addr() AS server_ip, current_database(), current_user;

-- Show all tenant rows as seen by the current session (no tenant set)
SELECT 'No app.current_tenant set (expected: zero rows because RLS blocks)' AS note;
SELECT COUNT(*) AS total_rows_visible FROM tenant_data;
SELECT * FROM tenant_data ORDER BY created_at LIMIT 20;

-- Set app.current_tenant to tenant A and show visible rows
SELECT 'Setting app.current_tenant = tenant A (1111...)' AS note;
SELECT set_config('app.current_tenant', '11111111-1111-1111-1111-111111111111', false) AS prev_value;

SELECT 'Rows visible to tenant A' AS note;
SELECT COUNT(*) AS count_for_tenant_a FROM tenant_data;
SELECT * FROM tenant_data ORDER BY created_at;

-- Call the function under tenant A (should return same rows)
SELECT 'Function get_tenant_data() output for tenant A' AS note;
SELECT * FROM get_tenant_data();

-- Switch to tenant B and show results (should be empty)
SELECT 'Switching to tenant B (2222...)' AS note;
SELECT set_config('app.current_tenant', '22222222-2222-2222-2222-222222222222', false) AS prev_value;

SELECT 'Rows visible to tenant B (expected: 0 if no rows for tenant B in seed)' AS note;
SELECT COUNT(*) AS count_for_tenant_b FROM tenant_data;
SELECT * FROM tenant_data ORDER BY created_at LIMIT 20;

-- Reset tenant setting to NULL (unset)
SELECT 'Unsetting app.current_tenant' AS note;
SELECT set_config('app.current_tenant', '', false) AS prev_value;

SELECT 'Final check - counts by tenant (bypassing RLS using aggregate on tenants join)' AS note;
-- This query will list counts per tenant (not bypassing RLS because it's a normal query,
-- but it shows the seeded data as intended when run by someone with DB access)
SELECT t.id AS tenant_id, t.name, COUNT(d.*) AS seeded_rows
FROM tenants t
LEFT JOIN tenant_data d ON d.tenant_id = t.id
GROUP BY t.id, t.name
ORDER BY t.name;

SELECT '--- DEMO END ---' AS note;
