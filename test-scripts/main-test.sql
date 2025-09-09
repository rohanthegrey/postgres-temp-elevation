-- PostgreSQL Temporary User Elevation - Main Test Script
-- This script demonstrates all the core functionality

\echo '================================================='
\echo 'PostgreSQL Temporary User Elevation - Test Suite'
\echo '================================================='
\echo ''

-- Set up environment
SET client_min_messages = NOTICE;
\timing on

\echo '=== 1. SYSTEM STATUS CHECK ==='
SELECT jsonb_pretty(temp_mgmt.get_system_status());

\echo ''
\echo '=== 2. INITIAL PERMISSIONS CHECK ==='
\echo 'Testing readonly_user permissions before elevation:'
SELECT * FROM temp_mgmt.test_user_permissions('readonly_user', 'app_data');

\echo ''
\echo '=== 3. CURRENT ACCESS GRANTS (should be empty initially) ==='
SELECT 
    username, 
    target_schema,
    status,
    granted_at,
    scheduled_revoke_at,
    hours_remaining
FROM temp_mgmt.check_temporary_access();

\echo ''
\echo '=== 4. GRANT TEMPORARY ACCESS ==='
\echo 'Granting write access to readonly_user for 1 hour:'
SELECT jsonb_pretty(
    temp_mgmt.grant_temporary_write_access(
        'readonly_user', 
        'app_data', 
        1, -- 1 hour
        ARRAY['INSERT', 'UPDATE', 'DELETE'],
        'Test run - demonstrating temporary elevation',
        'admin@example.com'
    )
);

\echo ''
\echo '=== 5. PERMISSIONS AFTER GRANT ==='
\echo 'Testing readonly_user permissions after elevation:'
SELECT * FROM temp_mgmt.test_user_permissions('readonly_user', 'app_data');

\echo ''
\echo '=== 6. ACTIVE GRANTS CHECK ==='
SELECT 
    username, 
    target_schema,
    permissions_granted,
    status,
    granted_at,
    scheduled_revoke_at,
    ROUND(hours_remaining, 2) as hours_remaining,
    reason,
    emergency_contact
FROM temp_mgmt.check_temporary_access();

\echo ''
\echo '=== 7. SYSTEM STATUS AFTER GRANT ==='
SELECT jsonb_pretty(temp_mgmt.get_system_status());

\echo ''
\echo '=== 8. ACTIVE CRON JOBS ==='
SELECT jobname, schedule, command FROM cron.job WHERE jobname LIKE 'revoke_%';

\echo ''
\echo '=== 9. TEST ACTUAL DATABASE OPERATIONS ==='
\echo 'Testing as readonly_user (should work now):'

-- Switch to readonly_user for testing (NOTE: This requires connection as that user)
-- For demonstration, we'll show what the queries would be:
\echo 'The following operations should now succeed when executed as readonly_user:'
\echo 'INSERT INTO app_data.users (name, email, department) VALUES (''Temp User'', ''temp@example.com'', ''Testing'');'
\echo 'UPDATE app_data.users SET department = ''Updated Testing'' WHERE email = ''temp@example.com'';'
\echo 'SELECT * FROM app_data.users WHERE email = ''temp@example.com'';'

\echo ''
\echo '=== 10. TRY TO CREATE DUPLICATE GRANT (should fail) ==='
SELECT jsonb_pretty(
    temp_mgmt.grant_temporary_write_access(
        'readonly_user', 
        'app_data', 
        2
    )
);

\echo ''
\echo '=== 11. EXTEND EXISTING GRANT ==='
\echo 'Extending readonly_user access by 30 minutes:'
SELECT jsonb_pretty(
    temp_mgmt.extend_temporary_access(
        'readonly_user',
        'app_data',
        1  -- Additional 1 hour
    )
);

\echo ''
\echo '=== 12. GRANTS AFTER EXTENSION ==='
SELECT 
    username, 
    target_schema,
    status,
    granted_at,
    scheduled_revoke_at,
    ROUND(hours_remaining, 2) as hours_remaining
FROM temp_mgmt.check_temporary_access();

\echo ''
\echo '=== 13. GRANT TO DIFFERENT USER ==='
\echo 'Granting write access to analyst_user for 30 minutes:'
SELECT jsonb_pretty(
    temp_mgmt.grant_temporary_write_access(
        'analyst_user', 
        'app_data', 
        1, -- 1 hour  
        ARRAY['INSERT', 'UPDATE'],  -- Limited permissions
        'Analyst needs to update test data'
    )
);

\echo ''
\echo '=== 14. ALL ACTIVE GRANTS ==='
SELECT 
    username, 
    target_schema,
    permissions_granted,
    status,
    granted_at,
    scheduled_revoke_at,
    ROUND(hours_remaining, 2) as hours_remaining,
    reason
FROM temp_mgmt.check_temporary_access() ORDER BY granted_at DESC;

\echo ''
\echo '=== 15. MANUAL REVOKE TEST ==='
\echo 'Manually revoking analyst_user access:'
SELECT jsonb_pretty(
    temp_mgmt.revoke_temporary_write_access('analyst_user', 'app_data')
);

\echo ''
\echo '=== 16. GRANTS AFTER MANUAL REVOKE ==='
SELECT 
    username, 
    target_schema,
    status,
    granted_at,
    revoked_at,
    CASE WHEN status = 'active' THEN ROUND(hours_remaining, 2) ELSE NULL END as hours_remaining
FROM temp_mgmt.check_temporary_access(NULL, NULL, true) -- Include expired
ORDER BY granted_at DESC;

\echo ''
\echo '=== 17. PERMISSIONS CHECK AFTER REVOKE ==='
SELECT * FROM temp_mgmt.test_user_permissions('analyst_user', 'app_data');

\echo ''
\echo '=== 18. FINAL SYSTEM STATUS ==='
SELECT jsonb_pretty(temp_mgmt.get_system_status());

\echo ''
\echo '=== 19. EMERGENCY REVOKE (OPTIONAL - UNCOMMENT TO TEST) ==='
\echo '-- Uncomment the next line to test emergency revoke:'
\echo '-- SELECT jsonb_pretty(temp_mgmt.emergency_revoke_all_access());'

\echo ''
\echo '=== 20. CLEANUP TEST DATA ==='
\echo 'Cleaning up any test records that may have been created:'
\echo 'DELETE FROM app_data.users WHERE email LIKE ''%temp%'' OR email LIKE ''%test%'';'

\echo ''
\echo '================================================='
\echo 'Test Complete!'
\echo '================================================='
\echo ''
\echo 'Notes:'
\echo '- readonly_user still has temporary write access (will expire automatically)'
\echo '- All operations are logged in temp_mgmt.temp_access_log'
\echo '- Cron jobs are scheduled for automatic revocation'
\echo '- Use emergency_revoke_all_access() if immediate revocation is needed'
\echo ''

