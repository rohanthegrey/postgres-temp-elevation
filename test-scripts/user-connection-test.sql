-- PostgreSQL Temporary User Elevation - User Connection Test
-- This script is designed to be run by the specific users to test their permissions

\echo '============================================='
\echo 'User Connection Test'
\echo 'Current User: ' :USER
\echo 'Current Database: ' :DBNAME
\echo 'Current Time: ' now()
\echo '============================================='

-- Show current user info
SELECT 
    current_user as connected_as,
    session_user as session_user,
    current_database() as database_name,
    inet_server_addr() as server_address,
    inet_server_port() as server_port;

\echo ''
\echo '=== TESTING READ PERMISSIONS ==='
\echo 'Attempting to read from app_data.users:'

SELECT 
    'READ TEST' as test_type,
    'app_data.users' as target_table,
    count(*) as record_count
FROM app_data.users;

\echo ''
\echo 'Attempting to read from app_data.orders:'
SELECT 
    'READ TEST' as test_type,
    'app_data.orders' as target_table,
    count(*) as record_count
FROM app_data.orders;

\echo ''
\echo '=== TESTING WRITE PERMISSIONS ==='

\echo ''
\echo 'Attempting INSERT (will succeed if write access granted):'
DO $$
DECLARE
    error_msg TEXT;
BEGIN
    BEGIN
        INSERT INTO app_data.users (name, email, department) 
        VALUES ('Test User - ' || current_user, 
                'test_' || current_user || '@example.com', 
                'Testing');
        
        RAISE NOTICE 'INSERT successful! Write access is ACTIVE.';
        
        -- Clean up the test record immediately
        DELETE FROM app_data.users 
        WHERE email = 'test_' || current_user || '@example.com';
        
        RAISE NOTICE 'Test record cleaned up successfully.';
        
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'INSERT failed: Insufficient privileges (read-only access)';
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_msg = MESSAGE_TEXT;
        RAISE NOTICE 'INSERT failed with error: %', error_msg;
    END;
END $$;

\echo ''
\echo 'Attempting UPDATE (will succeed if write access granted):'
DO $$
DECLARE
    error_msg TEXT;
    test_record_id INTEGER;
BEGIN
    BEGIN
        -- First, try to find any existing record to update
        SELECT id INTO test_record_id FROM app_data.users LIMIT 1;
        
        IF test_record_id IS NOT NULL THEN
            -- Store original value
            CREATE TEMP TABLE IF NOT EXISTS temp_update_test AS 
            SELECT id, name FROM app_data.users WHERE id = test_record_id;
            
            -- Attempt update
            UPDATE app_data.users 
            SET name = name || ' [TEMP TEST - ' || current_user || ']'
            WHERE id = test_record_id;
            
            RAISE NOTICE 'UPDATE successful! Write access is ACTIVE.';
            
            -- Restore original value
            UPDATE app_data.users 
            SET name = (SELECT name FROM temp_update_test WHERE id = test_record_id)
            WHERE id = test_record_id;
            
            RAISE NOTICE 'Original value restored successfully.';
            DROP TABLE IF EXISTS temp_update_test;
        ELSE
            RAISE NOTICE 'No records found to test UPDATE operation';
        END IF;
        
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'UPDATE failed: Insufficient privileges (read-only access)';
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_msg = MESSAGE_TEXT;
        RAISE NOTICE 'UPDATE failed with error: %', error_msg;
        -- Try to restore if temp table exists
        BEGIN
            UPDATE app_data.users 
            SET name = (SELECT name FROM temp_update_test WHERE id = test_record_id)
            WHERE id = test_record_id;
            DROP TABLE IF EXISTS temp_update_test;
        EXCEPTION WHEN OTHERS THEN
            -- Ignore cleanup errors
        END;
    END;
END $$;

\echo ''
\echo '=== SEQUENCE USAGE TEST ==='
DO $$
DECLARE
    error_msg TEXT;
    next_val INTEGER;
BEGIN
    BEGIN
        SELECT nextval('app_data.users_id_seq') INTO next_val;
        RAISE NOTICE 'SEQUENCE access successful! Can use nextval(): %', next_val;
        
        -- Don't reset the sequence as it might break inserts
        
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'SEQUENCE access failed: Insufficient privileges';
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_msg = MESSAGE_TEXT;
        RAISE NOTICE 'SEQUENCE access failed with error: %', error_msg;
    END;
END $$;

\echo ''
\echo '=== PERMISSION SUMMARY ==='
-- This will show the current effective permissions
SELECT 
    'app_data.users' as table_name,
    has_table_privilege(current_user, 'app_data.users', 'SELECT') as can_select,
    has_table_privilege(current_user, 'app_data.users', 'INSERT') as can_insert,
    has_table_privilege(current_user, 'app_data.users', 'UPDATE') as can_update,
    has_table_privilege(current_user, 'app_data.users', 'DELETE') as can_delete

UNION ALL

SELECT 
    'app_data.orders' as table_name,
    has_table_privilege(current_user, 'app_data.orders', 'SELECT') as can_select,
    has_table_privilege(current_user, 'app_data.orders', 'INSERT') as can_insert,
    has_table_privilege(current_user, 'app_data.orders', 'UPDATE') as can_update,
    has_table_privilege(current_user, 'app_data.orders', 'DELETE') as can_delete;

\echo ''
\echo '=== CHECK FOR ACTIVE TEMPORARY GRANTS ==='
-- Note: This will only work if the user has access to temp_mgmt schema
-- Otherwise, they should ask an admin to check their status
DO $$
DECLARE
    grant_info RECORD;
    error_msg TEXT;
BEGIN
    BEGIN
        SELECT 
            username,
            target_schema,
            granted_at,
            scheduled_revoke_at,
            hours_remaining,
            status
        INTO grant_info
        FROM temp_mgmt.check_temporary_access(current_user)
        WHERE status = 'active'
        LIMIT 1;
        
        IF FOUND THEN
            RAISE NOTICE 'ACTIVE TEMPORARY GRANT FOUND:';
            RAISE NOTICE '  User: %', grant_info.username;
            RAISE NOTICE '  Schema: %', grant_info.target_schema;
            RAISE NOTICE '  Granted: %', grant_info.granted_at;
            RAISE NOTICE '  Expires: %', grant_info.scheduled_revoke_at;
            RAISE NOTICE '  Hours remaining: %', ROUND(grant_info.hours_remaining, 2);
        ELSE
            RAISE NOTICE 'No active temporary grants found for current user';
        END IF;
        
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'Cannot check temporary grants: Insufficient privileges';
        RAISE NOTICE 'Ask an administrator to check your grant status';
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_msg = MESSAGE_TEXT;
        RAISE NOTICE 'Error checking grants: %', error_msg;
    END;
END $$;

\echo ''
\echo '============================================='
\echo 'User Connection Test Complete'
\echo 'User: ' :USER
\echo 'Time: ' now()
\echo '============================================='

