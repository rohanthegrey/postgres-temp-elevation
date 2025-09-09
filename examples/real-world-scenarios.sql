-- Real-World Scenarios for PostgreSQL Temporary User Elevation

\echo '================================================'
\echo 'Real-World Usage Scenarios'
\echo '================================================'

-- Scenario 1: Data Analyst needs temporary access to fix data quality issues
\echo ''
\echo '=== Scenario 1: Data Quality Fix ==='
\echo 'Analyst needs to update incorrect customer data discovered in reports'

SELECT jsonb_pretty(
    temp_mgmt.grant_temporary_write_access(
        'analyst_user',
        'app_data',
        3,  -- 3 hours should be enough
        ARRAY['UPDATE'],  -- Only UPDATE needed, no INSERT/DELETE
        'Fix customer data quality issues in users table - Ticket #QA-2024-001',
        'data-team@company.com'
    )
);

-- Show what the analyst can do now
\echo 'Analyst permissions after grant:'
SELECT * FROM temp_mgmt.test_user_permissions('analyst_user', 'app_data');

-- Scenario 2: Database migration task requiring extended access
\echo ''
\echo '=== Scenario 2: Database Migration Task ==='
\echo 'DBA needs extended access for overnight migration'

SELECT jsonb_pretty(
    temp_mgmt.grant_temporary_write_access(
        'migration_user',  -- Assuming this user exists
        'app_data',
        12,  -- 12 hours for overnight work
        ARRAY['INSERT', 'UPDATE', 'DELETE'],
        'Overnight data migration from legacy system - Project MIGRATE-2024',
        'dba-oncall@company.com'
    )
);

-- Scenario 3: Emergency data correction during business hours
\echo ''
\echo '=== Scenario 3: Emergency Data Correction ==='
\echo 'Support team needs immediate access to fix customer-impacting data issue'

SELECT jsonb_pretty(
    temp_mgmt.grant_temporary_write_access(
        'support_user',  -- Assuming this user exists
        'app_data',
        1,  -- Just 1 hour for quick fix
        ARRAY['UPDATE'],
        'URGENT: Fix incorrect order statuses affecting customer billing - Incident INC-2024-0456',
        'support-manager@company.com'
    )
);

-- Scenario 4: Audit compliance - extend access for additional investigation
\echo ''
\echo '=== Scenario 4: Audit Compliance Extension ==='
\echo 'Auditor needs more time to complete compliance checks'

-- First, simulate that auditor already has access
SELECT jsonb_pretty(
    temp_mgmt.grant_temporary_write_access(
        'auditor_user',  -- Assuming this user exists
        'app_data',
        2,  -- Initial 2 hours
        ARRAY['INSERT'],  -- Just INSERT for audit logs
        'Compliance audit data collection - Audit ID: AUD-2024-Q3-001',
        'compliance@company.com'
    )
);

-- Then extend it
\echo 'Extending auditor access due to complex findings:'
SELECT jsonb_pretty(
    temp_mgmt.extend_temporary_access(
        'auditor_user',
        'app_data',
        3  -- Add 3 more hours
    )
);

-- Scenario 5: Check all active emergency grants
\echo ''
\echo '=== Scenario 5: Security Review of All Active Grants ==='
\echo 'Security team reviewing all currently active temporary access grants'

SELECT 
    'SECURITY REVIEW - ACTIVE GRANTS' as review_type,
    username,
    target_schema,
    permissions_granted,
    granted_at,
    scheduled_revoke_at,
    ROUND(hours_remaining, 2) as hours_left,
    granted_by,
    reason,
    emergency_contact,
    CASE 
        WHEN hours_remaining > 8 THEN 'HIGH_DURATION'
        WHEN hours_remaining > 4 THEN 'MEDIUM_DURATION' 
        WHEN hours_remaining > 1 THEN 'NORMAL_DURATION'
        ELSE 'EXPIRING_SOON'
    END as duration_category
FROM temp_mgmt.check_temporary_access()
WHERE status = 'active'
ORDER BY hours_remaining DESC;

-- Scenario 6: Incident Response - Emergency revoke due to security concern
\echo ''
\echo '=== Scenario 6: Security Incident Response ==='
\echo 'Security incident detected - need to revoke all temporary access immediately'

-- This would be used in a real security incident
\echo 'In case of security incident, execute:'
\echo 'SELECT jsonb_pretty(temp_mgmt.emergency_revoke_all_access(NULL, ''Security incident INC-SEC-2024-001 - All temporary access revoked by security team''));'

-- Instead, let's just show current system status
SELECT jsonb_pretty(temp_mgmt.get_system_status());

-- Scenario 7: Scheduled maintenance - grant access to multiple users
\echo ''
\echo '=== Scenario 7: Scheduled Maintenance Window ==='
\echo 'Weekend maintenance requires multiple team members to have temporary access'

-- Grant to multiple users (in real scenario, you'd have these users)
DO $$
DECLARE
    maintenance_users TEXT[] := ARRAY['readonly_user', 'analyst_user'];
    user_name TEXT;
    result JSONB;
BEGIN
    FOREACH user_name IN ARRAY maintenance_users
    LOOP
        -- Skip if user already has access
        IF EXISTS (
            SELECT 1 FROM temp_mgmt.check_temporary_access(user_name) 
            WHERE status = 'active'
        ) THEN
            RAISE NOTICE 'User % already has active access, skipping', user_name;
            CONTINUE;
        END IF;
        
        SELECT temp_mgmt.grant_temporary_write_access(
            user_name,
            'app_data',
            8,  -- 8 hours for maintenance window
            ARRAY['INSERT', 'UPDATE', 'DELETE'],
            'Scheduled maintenance window - Maintenance ID: MAINT-2024-W42',
            'ops-team@company.com'
        ) INTO result;
        
        RAISE NOTICE 'Granted maintenance access to %: %', user_name, result->>'message';
    END LOOP;
END $$;

-- Scenario 8: Generate access report for management
\echo ''
\echo '=== Scenario 8: Management Reporting ==='
\echo 'Generate summary report of temporary access usage for management review'

WITH access_summary AS (
    SELECT 
        DATE(granted_at) as grant_date,
        COUNT(*) as total_grants,
        COUNT(*) FILTER (WHERE status = 'active') as currently_active,
        COUNT(*) FILTER (WHERE status = 'revoked') as manually_revoked,
        COUNT(*) FILTER (WHERE status = 'expired') as auto_expired,
        COUNT(*) FILTER (WHERE status = 'emergency_revoked') as emergency_revoked,
        AVG(EXTRACT(EPOCH FROM COALESCE(revoked_at, scheduled_revoke_at) - granted_at)/3600) as avg_duration_hours
    FROM temp_mgmt.temp_access_log
    WHERE granted_at >= CURRENT_DATE - INTERVAL '7 days'
    GROUP BY DATE(granted_at)
)
SELECT 
    grant_date,
    total_grants,
    currently_active,
    manually_revoked,
    auto_expired,
    emergency_revoked,
    ROUND(avg_duration_hours::NUMERIC, 2) as avg_duration_hours
FROM access_summary
ORDER BY grant_date DESC;

-- Show top users by access frequency
\echo ''
\echo 'Top users by temporary access frequency (last 7 days):'
SELECT 
    username,
    COUNT(*) as access_count,
    AVG(EXTRACT(EPOCH FROM COALESCE(revoked_at, scheduled_revoke_at) - granted_at)/3600) as avg_duration_hours,
    MAX(granted_at) as last_access
FROM temp_mgmt.temp_access_log
WHERE granted_at >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY username
ORDER BY access_count DESC, last_access DESC
LIMIT 5;

\echo ''
\echo '================================================'
\echo 'Real-World Scenarios Complete'
\echo '================================================'
\echo ''
\echo 'Key Takeaways:'
\echo '- Always provide clear reasons and emergency contacts'
\echo '- Use minimal necessary permissions (UPDATE only vs full write)'
\echo '- Monitor active grants regularly for security compliance'
\echo '- Have emergency revoke procedures ready'
\echo '- Generate regular reports for management oversight'

