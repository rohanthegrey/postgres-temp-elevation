-- PostgreSQL Temporary User Elevation - Utility Functions
-- This script creates additional utility functions for management and monitoring

SET search_path TO temp_mgmt, public;

-- Function to extend existing access
CREATE OR REPLACE FUNCTION temp_mgmt.extend_temporary_access(
    target_user TEXT,
    target_schema TEXT DEFAULT 'app_data',
    additional_hours INTEGER DEFAULT 1
) RETURNS JSONB AS $$
DECLARE
    log_record RECORD;
    new_revoke_time TIMESTAMP;
    old_job_name TEXT;
    new_job_name TEXT;
    job_id INTEGER;
BEGIN
    -- Validate inputs
    IF additional_hours <= 0 OR additional_hours > 24 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Additional hours must be between 1 and 24',
            'hours_requested', additional_hours
        );
    END IF;
    
    -- Get the current active grant
    SELECT * INTO log_record FROM temp_mgmt.temp_access_log 
    WHERE username = target_user 
      AND target_schema = extend_temporary_access.target_schema 
      AND status = 'active'
    ORDER BY granted_at DESC 
    LIMIT 1;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', format('No active grant found for user %s on schema %s', target_user, target_schema),
            'target_user', target_user,
            'target_schema', target_schema
        );
    END IF;
    
    -- Check if already expired
    IF log_record.scheduled_revoke_at <= NOW() THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Cannot extend expired access grant',
            'expired_at', log_record.scheduled_revoke_at,
            'current_time', NOW()
        );
    END IF;
    
    -- Calculate new revoke time
    new_revoke_time := log_record.scheduled_revoke_at + (additional_hours || ' hours')::INTERVAL;
    
    -- Remove old cron job
    FOR old_job_name IN 
        SELECT jobname FROM cron.job 
        WHERE jobname LIKE format('revoke_%s_%s_%%', target_user, target_schema)
    LOOP
        PERFORM cron.unschedule(old_job_name);
        RAISE NOTICE 'Removed old cron job: %', old_job_name;
    END LOOP;
    
    -- Create new cron job
    new_job_name := format('revoke_%s_%s_%s', target_user, target_schema, extract(epoch from now())::bigint);
    
    SELECT cron.schedule(
        new_job_name,
        format('%s %s %s %s *', 
            extract(minute from new_revoke_time)::int,
            extract(hour from new_revoke_time)::int,
            extract(day from new_revoke_time)::int,
            extract(month from new_revoke_time)::int
        ),
        format('SELECT temp_mgmt.revoke_temporary_write_access(%L, %L, true)', target_user, target_schema)
    ) INTO job_id;
    
    -- Update the log record
    UPDATE temp_mgmt.temp_access_log 
    SET 
        scheduled_revoke_at = new_revoke_time,
        job_id = job_id::text
    WHERE id = log_record.id;
    
    RAISE NOTICE 'Extended access for % on % until % (New Job: %)', 
        target_user, target_schema, new_revoke_time, job_id;
    
    RETURN jsonb_build_object(
        'success', true,
        'message', format('Extended access for %s on %s by %s hours', target_user, target_schema, additional_hours),
        'target_user', target_user,
        'target_schema', target_schema,
        'previous_expires_at', log_record.scheduled_revoke_at,
        'new_expires_at', new_revoke_time,
        'additional_hours', additional_hours,
        'total_hours_remaining', ROUND(EXTRACT(EPOCH FROM (new_revoke_time - NOW()))/3600, 2),
        'new_job_id', job_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to emergency revoke all access
CREATE OR REPLACE FUNCTION temp_mgmt.emergency_revoke_all_access(
    target_schema TEXT DEFAULT NULL,
    reason TEXT DEFAULT 'Emergency revocation by administrator'
) RETURNS JSONB AS $$
DECLARE
    r RECORD;
    revoked_count INTEGER := 0;
    results JSONB[] := '{}';
    result JSONB;
BEGIN
    RAISE WARNING 'EMERGENCY REVOKE INITIATED by % at %', CURRENT_USER, NOW();
    
    FOR r IN 
        SELECT username, target_schema 
        FROM temp_mgmt.temp_access_log 
        WHERE status = 'active'
          AND (emergency_revoke_all_access.target_schema IS NULL OR target_schema = emergency_revoke_all_access.target_schema)
    LOOP
        -- Revoke access
        SELECT temp_mgmt.revoke_temporary_write_access(r.username, r.target_schema) INTO result;
        results := results || result;
        
        -- Update status to emergency_revoked
        UPDATE temp_mgmt.temp_access_log 
        SET status = 'emergency_revoked', reason = emergency_revoke_all_access.reason
        WHERE username = r.username 
          AND target_schema = r.target_schema 
          AND status IN ('active', 'revoked');
        
        revoked_count := revoked_count + 1;
        
        RAISE WARNING 'Emergency revoked: %@%', r.username, r.target_schema;
    END LOOP;
    
    -- Remove all related cron jobs
    PERFORM cron.unschedule(jobname) 
    FROM cron.job 
    WHERE jobname LIKE 'revoke_%';
    
    RAISE WARNING 'EMERGENCY REVOKE COMPLETED: % grants revoked', revoked_count;
    
    RETURN jsonb_build_object(
        'success', true,
        'message', format('Emergency revoke completed: %s grants revoked', revoked_count),
        'revoked_count', revoked_count,
        'revoked_at', NOW(),
        'revoked_by', CURRENT_USER,
        'reason', reason,
        'details', results
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to test user permissions
CREATE OR REPLACE FUNCTION temp_mgmt.test_user_permissions(
    target_user TEXT,
    target_schema TEXT DEFAULT 'app_data'
) RETURNS TABLE(
    operation TEXT,
    permission TEXT,
    result TEXT,
    details TEXT
) AS $$
DECLARE
    test_table TEXT;
BEGIN
    -- Find a table in the target schema for testing
    SELECT table_name INTO test_table
    FROM information_schema.tables 
    WHERE table_schema = target_schema 
      AND table_type = 'BASE TABLE'
    LIMIT 1;
    
    IF test_table IS NULL THEN
        RETURN QUERY SELECT 
            'ERROR'::TEXT, 
            'N/A'::TEXT, 
            'FAILED'::TEXT, 
            format('No tables found in schema %s', target_schema)::TEXT;
        RETURN;
    END IF;
    
    -- Test SELECT permission
    RETURN QUERY SELECT 
        'READ'::TEXT as operation,
        'SELECT'::TEXT as permission,
        CASE 
            WHEN has_table_privilege(target_user, target_schema || '.' || test_table, 'SELECT') 
            THEN 'ALLOWED' 
            ELSE 'DENIED' 
        END::TEXT as result,
        format('SELECT on %s.%s', target_schema, test_table)::TEXT as details;
    
    -- Test INSERT permission
    RETURN QUERY SELECT 
        'WRITE'::TEXT as operation,
        'INSERT'::TEXT as permission,
        CASE 
            WHEN has_table_privilege(target_user, target_schema || '.' || test_table, 'INSERT') 
            THEN 'ALLOWED' 
            ELSE 'DENIED' 
        END::TEXT as result,
        format('INSERT on %s.%s', target_schema, test_table)::TEXT as details;
    
    -- Test UPDATE permission
    RETURN QUERY SELECT 
        'WRITE'::TEXT as operation,
        'UPDATE'::TEXT as permission,
        CASE 
            WHEN has_table_privilege(target_user, target_schema || '.' || test_table, 'UPDATE') 
            THEN 'ALLOWED' 
            ELSE 'DENIED' 
        END::TEXT as result,
        format('UPDATE on %s.%s', target_schema, test_table)::TEXT as details;
    
    -- Test DELETE permission
    RETURN QUERY SELECT 
        'WRITE'::TEXT as operation,
        'DELETE'::TEXT as permission,
        CASE 
            WHEN has_table_privilege(target_user, target_schema || '.' || test_table, 'DELETE') 
            THEN 'ALLOWED' 
            ELSE 'DENIED' 
        END::TEXT as result,
        format('DELETE on %s.%s', target_schema, test_table)::TEXT as details;
    
    -- Test SEQUENCE usage (for INSERT operations)
    RETURN QUERY
    SELECT 
        'SEQUENCE'::TEXT as operation,
        'USAGE'::TEXT as permission,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM information_schema.sequences s
                WHERE s.sequence_schema = target_schema
                  AND has_sequence_privilege(target_user, target_schema || '.' || s.sequence_name, 'USAGE')
            )
            THEN 'ALLOWED'
            ELSE 'DENIED'
        END::TEXT as result,
        format('USAGE on sequences in %s', target_schema)::TEXT as details;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to cleanup expired grants (maintenance)
CREATE OR REPLACE FUNCTION temp_mgmt.cleanup_expired_grants() RETURNS JSONB AS $$
DECLARE
    expired_count INTEGER;
    cleanup_results JSONB[] := '{}';
    r RECORD;
    result JSONB;
BEGIN
    -- Find and process expired grants
    FOR r IN 
        SELECT username, target_schema, id
        FROM temp_mgmt.temp_access_log 
        WHERE status = 'active' 
          AND scheduled_revoke_at <= NOW()
    LOOP
        -- Revoke the expired access
        SELECT temp_mgmt.revoke_temporary_write_access(r.username, r.target_schema, true) INTO result;
        cleanup_results := cleanup_results || result;
        
        -- Update status to expired (already done by revoke function, but being explicit)
        UPDATE temp_mgmt.temp_access_log 
        SET status = 'expired'
        WHERE id = r.id;
    END LOOP;
    
    GET DIAGNOSTICS expired_count = ROW_COUNT;
    
    -- Clean up old cron jobs that might be stuck
    PERFORM cron.unschedule(jobname) 
    FROM cron.job 
    WHERE jobname LIKE 'revoke_%'
      AND NOT EXISTS (
          SELECT 1 FROM temp_mgmt.temp_access_log 
          WHERE status = 'active' 
            AND job_id = (regexp_match(jobname, 'revoke_.*?_.*?_(\d+)'))[1]
      );
    
    RETURN jsonb_build_object(
        'success', true,
        'message', format('Cleanup completed: %s expired grants processed', expired_count),
        'expired_grants_processed', expired_count,
        'cleanup_time', NOW(),
        'details', cleanup_results
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get system status and statistics
CREATE OR REPLACE FUNCTION temp_mgmt.get_system_status() RETURNS JSONB AS $$
DECLARE
    stats JSONB;
BEGIN
    WITH status_counts AS (
        SELECT 
            status,
            COUNT(*) as count
        FROM temp_mgmt.temp_access_log
        GROUP BY status
    ),
    active_grants AS (
        SELECT 
            COUNT(*) as active_count,
            MIN(scheduled_revoke_at) as next_expiry,
            MAX(scheduled_revoke_at) as last_expiry
        FROM temp_mgmt.temp_access_log
        WHERE status = 'active'
    ),
    cron_jobs AS (
        SELECT COUNT(*) as job_count
        FROM cron.job 
        WHERE jobname LIKE 'revoke_%'
    )
    SELECT jsonb_build_object(
        'current_time', NOW(),
        'total_grants_ever', COALESCE((SELECT SUM(count) FROM status_counts), 0),
        'status_breakdown', jsonb_object_agg(status, count) FILTER (WHERE status IS NOT NULL),
        'active_grants', jsonb_build_object(
            'count', COALESCE(active_count, 0),
            'next_expiry', next_expiry,
            'last_expiry', last_expiry
        ),
        'scheduled_cron_jobs', COALESCE(job_count, 0),
        'system_health', CASE 
            WHEN EXISTS (SELECT 1 FROM temp_mgmt.temp_access_log WHERE status = 'active' AND scheduled_revoke_at <= NOW()) 
            THEN 'WARNING: Expired grants detected'
            ELSE 'OK'
        END
    ) INTO stats
    FROM status_counts 
    FULL OUTER JOIN active_grants ON true
    FULL OUTER JOIN cron_jobs ON true;
    
    RETURN stats;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create a maintenance job that runs every hour to clean up expired grants
SELECT cron.schedule(
    'cleanup_expired_grants',
    '0 * * * *',  -- Every hour at minute 0
    'SELECT temp_mgmt.cleanup_expired_grants();'
);

-- Grant necessary permissions to admin user
GRANT ALL ON SCHEMA temp_mgmt TO admin;
GRANT ALL ON ALL TABLES IN SCHEMA temp_mgmt TO admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA temp_mgmt TO admin;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA temp_mgmt TO admin;

-- Log completion
DO $$
BEGIN
    RAISE NOTICE 'Utility functions setup completed successfully!';
    RAISE NOTICE 'Available functions:';
    RAISE NOTICE '- temp_mgmt.grant_temporary_write_access()';
    RAISE NOTICE '- temp_mgmt.revoke_temporary_write_access()';
    RAISE NOTICE '- temp_mgmt.extend_temporary_access()';
    RAISE NOTICE '- temp_mgmt.check_temporary_access()';
    RAISE NOTICE '- temp_mgmt.test_user_permissions()';
    RAISE NOTICE '- temp_mgmt.emergency_revoke_all_access()';
    RAISE NOTICE '- temp_mgmt.cleanup_expired_grants()';
    RAISE NOTICE '- temp_mgmt.get_system_status()';
    RAISE NOTICE 'Automatic cleanup job scheduled to run every hour';
END $$;

