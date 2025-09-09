-- PostgreSQL Temporary User Elevation - Core Functions
-- This script creates the temporary elevation management system

SET search_path TO temp_mgmt, public;

-- Create the audit log table for tracking temporary access grants
CREATE TABLE IF NOT EXISTS temp_mgmt.temp_access_log (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) NOT NULL,
    target_schema VARCHAR(255) NOT NULL,
    permissions_granted TEXT[] NOT NULL DEFAULT '{}',
    granted_at TIMESTAMP DEFAULT NOW(),
    scheduled_revoke_at TIMESTAMP NOT NULL,
    revoked_at TIMESTAMP,
    granted_by VARCHAR(255) DEFAULT CURRENT_USER,
    revoked_by VARCHAR(255),
    status VARCHAR(50) DEFAULT 'active',
    job_id TEXT,
    reason TEXT,
    emergency_contact VARCHAR(255),
    CONSTRAINT valid_status CHECK (status IN ('active', 'revoked', 'expired', 'emergency_revoked'))
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_temp_access_username_status
    ON temp_mgmt.temp_access_log(username, status);
CREATE INDEX IF NOT EXISTS idx_temp_access_schema_status
    ON temp_mgmt.temp_access_log(target_schema, status);
CREATE INDEX IF NOT EXISTS idx_temp_access_scheduled_revoke
    ON temp_mgmt.temp_access_log(scheduled_revoke_at) WHERE status = 'active';

-- Function to grant temporary write access
CREATE OR REPLACE FUNCTION temp_mgmt.grant_temporary_write_access(
    target_user TEXT,
    target_schema TEXT DEFAULT 'app_data',
    duration_hours INTEGER DEFAULT 2,
    permissions TEXT[] DEFAULT ARRAY['INSERT', 'UPDATE', 'DELETE'],
    reason TEXT DEFAULT NULL,
    emergency_contact TEXT DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
    job_id INTEGER;
    revoke_time TIMESTAMP;
    job_name TEXT;
    existing_grant RECORD;
    perm TEXT;
    result JSONB;
BEGIN
    -- Validate inputs
    IF duration_hours <= 0 OR duration_hours > 168 THEN  -- Max 1 week
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Duration must be between 1 and 168 hours (1 week max)',
            'hours_requested', duration_hours
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = target_user) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', format('User %s does not exist', target_user),
            'target_user', target_user
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = target_schema) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', format('Schema %s does not exist', target_schema),
            'target_schema', target_schema
        );
    END IF;

    -- Check for existing active grants
    SELECT * INTO existing_grant FROM temp_mgmt.temp_access_log
    WHERE username = target_user
      AND target_schema = grant_temporary_write_access.target_schema
      AND status = 'active';

    IF FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', format('User %s already has active temporary access to schema %s', target_user, target_schema),
            'existing_grant_id', existing_grant.id,
            'existing_expires_at', existing_grant.scheduled_revoke_at,
            'existing_hours_remaining', ROUND(EXTRACT(EPOCH FROM (existing_grant.scheduled_revoke_at - NOW()))/3600, 2)
        );
    END IF;

    -- Calculate revoke time
    revoke_time := NOW() + (duration_hours || ' hours')::INTERVAL;
    job_name := format('revoke_%s_%s_%s', target_user, target_schema, extract(epoch from now())::bigint);

    -- Grant permissions
    FOREACH perm IN ARRAY permissions
    LOOP
        EXECUTE format('GRANT %s ON ALL TABLES IN SCHEMA %I TO %I', perm, target_schema, target_user);

        -- Also grant on sequences if needed
        IF perm IN ('INSERT', 'UPDATE') THEN
            EXECUTE format('GRANT USAGE ON ALL SEQUENCES IN SCHEMA %I TO %I', target_schema, target_user);
        END IF;
    END LOOP;

    -- Schedule the revoke job using pg_cron
    BEGIN
        SELECT cron.schedule(
            job_name,
            format('%s %s %s %s *',
                extract(minute from revoke_time)::int,
                extract(hour from revoke_time)::int,
                extract(day from revoke_time)::int,
                extract(month from revoke_time)::int
            ),
            format('SELECT temp_mgmt.revoke_temporary_write_access(%L, %L, true)', target_user, target_schema)
        ) INTO job_id;
    EXCEPTION WHEN OTHERS THEN
        -- Rollback permissions if scheduling fails
        FOREACH perm IN ARRAY permissions
        LOOP
            EXECUTE format('REVOKE %s ON ALL TABLES IN SCHEMA %I FROM %I', perm, target_schema, target_user);
            IF perm IN ('INSERT', 'UPDATE') THEN
                EXECUTE format('REVOKE USAGE ON ALL SEQUENCES IN SCHEMA %I FROM %I', target_schema, target_user);
            END IF;
        END LOOP;

        RETURN jsonb_build_object(
            'success', false,
            'error', format('Failed to schedule revoke job: %s', SQLERRM),
            'details', 'Permissions were rolled back'
        );
    END;

    -- Log the grant
    INSERT INTO temp_mgmt.temp_access_log
        (username, target_schema, permissions_granted, scheduled_revoke_at, job_id, reason, emergency_contact)
    VALUES
        (target_user, target_schema, permissions, revoke_time, job_id::text, reason, emergency_contact);

    -- Build success response
    result := jsonb_build_object(
        'success', true,
        'message', format('Write access granted to %s on schema %s', target_user, target_schema),
        'target_user', target_user,
        'target_schema', target_schema,
        'permissions_granted', permissions,
        'duration_hours', duration_hours,
        'granted_at', NOW(),
        'expires_at', revoke_time,
        'job_id', job_id,
        'cron_job_name', job_name
    );

    IF reason IS NOT NULL THEN
        result := result || jsonb_build_object('reason', reason);
    END IF;

    IF emergency_contact IS NOT NULL THEN
        result := result || jsonb_build_object('emergency_contact', emergency_contact);
    END IF;

    -- Log success
    RAISE NOTICE 'Temporary access granted: % on % until % (Job: %)',
        target_user, target_schema, revoke_time, job_id;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to revoke write access
CREATE OR REPLACE FUNCTION temp_mgmt.revoke_temporary_write_access(
    target_user TEXT,
    target_schema TEXT DEFAULT 'app_data',
    auto_revoke BOOLEAN DEFAULT false
) RETURNS JSONB AS $$
DECLARE
    job_name TEXT;
    log_record RECORD;
    perm TEXT;
    revoke_type TEXT;
BEGIN
    -- Get the current grant info
    SELECT * INTO log_record FROM temp_mgmt.temp_access_log
    WHERE username = target_user
      AND target_schema = revoke_temporary_write_access.target_schema
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

    -- Determine revoke type
    revoke_type := CASE
        WHEN auto_revoke THEN 'expired'
        ELSE 'revoked'
    END;

    -- Revoke permissions
    FOREACH perm IN ARRAY log_record.permissions_granted
    LOOP
        BEGIN
            EXECUTE format('REVOKE %s ON ALL TABLES IN SCHEMA %I FROM %I', perm, target_schema, target_user);

            IF perm IN ('INSERT', 'UPDATE') THEN
                EXECUTE format('REVOKE USAGE ON ALL SEQUENCES IN SCHEMA %I FROM %I', target_schema, target_user);
            END IF;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Failed to revoke % permission from %: %', perm, target_user, SQLERRM;
        END;
    END LOOP;

    -- Update log
    UPDATE temp_mgmt.temp_access_log
    SET
        revoked_at = NOW(),
        status = revoke_type,
        revoked_by = CASE WHEN auto_revoke THEN 'system' ELSE CURRENT_USER END
    WHERE id = log_record.id;

    -- Remove scheduled cron job if not auto-revoke
    IF NOT auto_revoke AND log_record.job_id IS NOT NULL THEN
        FOR job_name IN
            SELECT jobname FROM cron.job
            WHERE jobname LIKE format('revoke_%s_%s_%%', target_user, target_schema)
        LOOP
            BEGIN
                PERFORM cron.unschedule(job_name);
                RAISE NOTICE 'Unscheduled cron job: %', job_name;
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING 'Failed to unschedule job %: %', job_name, SQLERRM;
            END;
        END LOOP;
    END IF;

    -- Log success
    RAISE NOTICE 'Access revoked: % from % on % (%)',
        target_user, target_schema,
        CASE WHEN auto_revoke THEN 'auto-expired' ELSE 'manually revoked' END,
        NOW();

    RETURN jsonb_build_object(
        'success', true,
        'message', format('Write access %s from %s on schema %s',
            CASE WHEN auto_revoke THEN 'expired' ELSE 'revoked' END,
            target_user, target_schema),
        'target_user', target_user,
        'target_schema', target_schema,
        'permissions_revoked', log_record.permissions_granted,
        'revoked_at', NOW(),
        'revoke_type', revoke_type,
        'grant_duration', NOW() - log_record.granted_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to check current temporary access grants
CREATE OR REPLACE FUNCTION temp_mgmt.check_temporary_access(
    filter_user TEXT DEFAULT NULL,
    filter_schema TEXT DEFAULT NULL,
    include_expired BOOLEAN DEFAULT false
) RETURNS TABLE(
    id INTEGER,
    username TEXT,
    target_schema TEXT,
    permissions_granted TEXT[],
    granted_at TIMESTAMP,
    scheduled_revoke_at TIMESTAMP,
    revoked_at TIMESTAMP,
    granted_by TEXT,
    revoked_by TEXT,
    status TEXT,
    reason TEXT,
    emergency_contact TEXT,
    time_remaining INTERVAL,
    hours_remaining NUMERIC,
    is_expired BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.id,
        t.username::TEXT,
        t.target_schema::TEXT,
        t.permissions_granted,
        t.granted_at,
        t.scheduled_revoke_at,
        t.revoked_at,
        t.granted_by::TEXT,
        t.revoked_by::TEXT,
        t.status::TEXT,
        t.reason::TEXT,
        t.emergency_contact::TEXT,
        CASE
            WHEN t.status = 'active' AND t.scheduled_revoke_at > NOW() THEN
                t.scheduled_revoke_at - NOW()
            ELSE NULL
        END as time_remaining,
        CASE
            WHEN t.status = 'active' AND t.scheduled_revoke_at > NOW() THEN
                ROUND(EXTRACT(EPOCH FROM (t.scheduled_revoke_at - NOW()))/3600, 2)
            ELSE NULL
        END as hours_remaining,
        CASE
            WHEN t.status = 'active' AND t.scheduled_revoke_at <= NOW() THEN true
            ELSE false
        END as is_expired
    FROM temp_mgmt.temp_access_log t
    WHERE
        (filter_user IS NULL OR t.username = filter_user)
        AND (filter_schema IS NULL OR t.target_schema = filter_schema)
        AND (include_expired OR t.status = 'active')
    ORDER BY
        CASE WHEN t.status = 'active' THEN 0 ELSE 1 END,
        t.granted_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
