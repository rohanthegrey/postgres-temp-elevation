-- Basic Usage Examples for PostgreSQL Temporary User Elevation

\echo '=========================================='
\echo 'Basic Usage Examples'
\echo '=========================================='

-- Example 1: Grant basic write access for 2 hours
\echo ''
\echo '=== Example 1: Basic Write Access Grant ==='
SELECT jsonb_pretty(
    temp_mgmt.grant_temporary_write_access(
        'readonly_user',      -- Target user
        'app_data',          -- Target schema  
        2                    -- Duration in hours
    )
);

-- Example 2: Grant with specific permissions and metadata
\echo ''
\echo '=== Example 2: Detailed Grant with Metadata ==='
SELECT jsonb_pretty(
    temp_mgmt.grant_temporary_write_access(
        'analyst_user',                           -- Target user
        'app_data',                              -- Target schema
        4,                                       -- Duration: 4 hours
        ARRAY['INSERT', 'UPDATE'],               -- Specific permissions
        'Data migration task #1234',             -- Reason
        'dba-team@company.com'                   -- Emergency contact
    )
);

-- Example 3: Check current access grants
\echo ''
\echo '=== Example 3: Check All Active Grants ==='
SELECT 
    username,
    target_schema,
    permissions_granted,
    granted_at,
    scheduled_revoke_at,
    ROUND(hours_remaining, 2) as hours_left,
    reason
FROM temp_mgmt.check_temporary_access()
WHERE status = 'active';

-- Example 4: Check grants for specific user
\echo ''
\echo '=== Example 4: Check Grants for Specific User ==='
SELECT 
    username,
    target_schema,
    status,
    granted_at,
    revoked_at,
    reason
FROM temp_mgmt.check_temporary_access('readonly_user')
ORDER BY granted_at DESC
LIMIT 5;

-- Example 5: Test user permissions
\echo ''
\echo '=== Example 5: Test User Permissions ==='
SELECT * FROM temp_mgmt.test_user_permissions('readonly_user', 'app_data');

-- Example 6: Extend existing access
\echo ''
\echo '=== Example 6: Extend Access (if active grant exists) ==='
-- This will only work if readonly_user has an active grant
SELECT jsonb_pretty(
    temp_mgmt.extend_temporary_access(
        'readonly_user',
        'app_data', 
        2  -- Extend by 2 hours
    )
);

-- Example 7: Manual revoke
\echo ''
\echo '=== Example 7: Manual Revoke Access ==='
SELECT jsonb_pretty(
    temp_mgmt.revoke_temporary_write_access(
        'analyst_user',
        'app_data'
    )
);

-- Example 8: Get system status
\echo ''
\echo '=== Example 8: System Status and Statistics ==='
SELECT jsonb_pretty(temp_mgmt.get_system_status());

-- Example 9: Emergency revoke all (commented out for safety)
\echo ''
\echo '=== Example 9: Emergency Revoke (COMMENTED OUT) ==='
\echo '-- Uncomment to test emergency revoke:'
\echo '-- SELECT jsonb_pretty(temp_mgmt.emergency_revoke_all_access());'

-- Example 10: Cleanup expired grants manually
\echo ''
\echo '=== Example 10: Manual Cleanup ==='
SELECT jsonb_pretty(temp_mgmt.cleanup_expired_grants());

\echo ''
\echo '=========================================='
\echo 'Examples Complete'
\echo '=========================================='

