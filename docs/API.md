# PostgreSQL Temporary User Elevation - API Reference

## Core Functions

### `grant_temporary_write_access()`

Grants temporary write permissions to a database user for a specified duration.

**Signature:**
```sql
temp_mgmt.grant_temporary_write_access(
    target_user TEXT,              -- Required: Database user to grant access
    target_schema TEXT DEFAULT 'app_data',  -- Schema to grant access on
    duration_hours INTEGER DEFAULT 2,       -- Duration in hours (1-168)
    permissions TEXT[] DEFAULT ARRAY['INSERT', 'UPDATE', 'DELETE'],  -- Permissions to grant
    reason TEXT DEFAULT NULL,                -- Reason for access grant
    emergency_contact TEXT DEFAULT NULL     -- Emergency contact information
) RETURNS JSONB
```

**Parameters:**
- `target_user` (TEXT, required): Database user that will receive temporary access
- `target_schema` (TEXT, optional): Schema to grant permissions on (default: 'app_data')
- `duration_hours` (INTEGER, optional): How long access should last in hours (1-168, default: 2)
- `permissions` (TEXT[], optional): Array of permissions to grant (default: ['INSERT', 'UPDATE', 'DELETE'])
- `reason` (TEXT, optional): Business reason or ticket number for the access grant
- `emergency_contact` (TEXT, optional): Contact person in case of issues

**Returns:** JSONB object with operation result
```json
{
  "success": true,
  "message": "Write access granted to readonly_user on schema app_data",
  "target_user": "readonly_user",
  "target_schema": "app_data",
  "permissions_granted": ["INSERT", "UPDATE", "DELETE"],
  "duration_hours": 2,
  "granted_at": "2024-03-15T10:30:00Z",
  "expires_at": "2024-03-15T12:30:00Z",
  "job_id": 12345,
  "cron_job_name": "revoke_readonly_user_app_data_1710507000"
}
```

**Error Response:**
```json
{
  "success": false,
  "error": "User readonly_user already has active temporary access to schema app_data",
  "existing_grant_id": 123,
  "existing_expires_at": "2024-03-15T12:30:00Z",
  "existing_hours_remaining": 1.5
}
```

**Examples:**
```sql
-- Basic usage
SELECT temp_mgmt.grant_temporary_write_access('readonly_user');

-- Custom duration and permissions  
SELECT temp_mgmt.grant_temporary_write_access(
    'analyst_user',
    'app_data', 
    4,
    ARRAY['UPDATE'],
    'Fix customer data - Ticket #123'
);

-- Full parameters
SELECT temp_mgmt.grant_temporary_write_access(
    'support_user',
    'app_data',
    1,
    ARRAY['INSERT', 'UPDATE'],
    'Emergency customer billing fix - INC-456',
    'support-manager@company.com'
);
```

---

### `revoke_temporary_write_access()`

Revokes temporary write permissions from a database user.

**Signature:**
```sql
temp_mgmt.revoke_temporary_write_access(
    target_user TEXT,              -- Required: User to revoke access from
    target_schema TEXT DEFAULT 'app_data',  -- Schema to revoke access on
    auto_revoke BOOLEAN DEFAULT false       -- Internal: whether this is automatic
) RETURNS JSONB
```

**Parameters:**
- `target_user` (TEXT, required): Database user to revoke access from
- `target_schema` (TEXT, optional): Schema to revoke permissions on (default: 'app_data')
- `auto_revoke` (BOOLEAN, internal): Used internally by the system for automatic revocation

**Returns:** JSONB object with operation result
```json
{
  "success": true,
  "message": "Write access revoked from readonly_user on schema app_data",
  "target_user": "readonly_user",
  "target_schema": "app_data", 
  "permissions_revoked": ["INSERT", "UPDATE", "DELETE"],
  "revoked_at": "2024-03-15T11:15:00Z",
  "revoke_type": "revoked",
  "grant_duration": "00:45:00"
}
```

**Examples:**
```sql
-- Basic revoke
SELECT temp_mgmt.revoke_temporary_write_access('readonly_user');

-- Revoke from specific schema
SELECT temp_mgmt.revoke_temporary_write_access('analyst_user', 'reporting');
```

---

### `check_temporary_access()`

Returns information about current and past temporary access grants.

**Signature:**
```sql
temp_mgmt.check_temporary_access(
    filter_user TEXT DEFAULT NULL,         -- Filter by specific user
    filter_schema TEXT DEFAULT NULL,       -- Filter by specific schema
    include_expired BOOLEAN DEFAULT false  -- Include expired grants
) RETURNS TABLE(...)
```

**Parameters:**
- `filter_user` (TEXT, optional): Show grants only for this user
- `filter_schema` (TEXT, optional): Show grants only for this schema
- `include_expired` (BOOLEAN, optional): Include expired/revoked grants (default: false)

**Returns:** Table with the following columns:
- `id` (INTEGER): Unique grant ID
- `username` (TEXT): Database user
- `target_schema` (TEXT): Target schema
- `permissions_granted` (TEXT[]): Array of granted permissions
- `granted_at` (TIMESTAMP): When access was granted
- `scheduled_revoke_at` (TIMESTAMP): When access is scheduled to expire
- `revoked_at` (TIMESTAMP): When access was actually revoked (if applicable)
- `granted_by` (TEXT): Who granted the access
- `revoked_by` (TEXT): Who revoked the access
- `status` (TEXT): Current status ('active', 'revoked', 'expired', 'emergency_revoked')
- `reason` (TEXT): Reason for the grant
- `emergency_contact` (TEXT): Emergency contact
- `time_remaining` (INTERVAL): Time until expiration (active grants only)
- `hours_remaining` (NUMERIC): Hours until expiration (active grants only)
- `is_expired` (BOOLEAN): Whether the grant has passed its expiration time

**Examples:**
```sql
-- Show all active grants
SELECT * FROM temp_mgmt.check_temporary_access();

-- Show all grants for specific user (including expired)
SELECT * FROM temp_mgmt.check_temporary_access('readonly_user', NULL, true);

-- Show grants for specific schema
SELECT * FROM temp_mgmt.check_temporary_access(NULL, 'app_data');

-- Get just the essentials for active grants
SELECT 
    username,
    target_schema, 
    permissions_granted,
    ROUND(hours_remaining, 2) as hours_left,
    reason
FROM temp_mgmt.check_temporary_access()
WHERE status = 'active';
```

---

### `extend_temporary_access()`

Extends the duration of an existing active temporary access grant.

**Signature:**
```sql
temp_mgmt.extend_temporary_access(
    target_user TEXT,              -- Required: User with existing access
    target_schema TEXT DEFAULT 'app_data',  -- Schema with existing access
    additional_hours INTEGER DEFAULT 1      -- Hours to add (1-24)
) RETURNS JSONB
```

**Parameters:**
- `target_user` (TEXT, required): User with existing active grant
- `target_schema` (TEXT, optional): Schema with existing access (default: 'app_data')  
- `additional_hours` (INTEGER, optional): Hours to add to existing grant (1-24, default: 1)

**Returns:** JSONB object with operation result
```json
{
  "success": true,
  "message": "Extended access for readonly_user on app_data by 2 hours",
  "target_user": "readonly_user",
  "target_schema": "app_data",
  "previous_expires_at": "2024-03-15T12:30:00Z",
  "new_expires_at": "2024-03-15T14:30:00Z", 
  "additional_hours": 2,
  "total_hours_remaining": 3.25,
  "new_job_id": 12346
}
```

**Examples:**
```sql
-- Extend by 1 hour (default)
SELECT temp_mgmt.extend_temporary_access('readonly_user');

-- Extend by specific amount
SELECT temp_mgmt.extend_temporary_access(
    'analyst_user',
    'app_data',
    3  -- Add 3 more hours
);
```

---

### `test_user_permissions()`

Tests what permissions a user currently has on a given schema.

**Signature:**
```sql
temp_mgmt.test_user_permissions(
    target_user TEXT,              -- Required: User to test
    target_schema TEXT DEFAULT 'app_data'   -- Schema to test
) RETURNS TABLE(...)
```

**Parameters:**
- `target_user` (TEXT, required): Database user to test permissions for
- `target_schema` (TEXT, optional): Schema to test permissions on (default: 'app_data')

**Returns:** Table with the following columns:
- `operation` (TEXT): Type of operation ('READ', 'WRITE', 'UPDATE', 'DELETE', 'SEQUENCE')
- `permission` (TEXT): Specific permission being tested ('SELECT', 'INSERT', 'UPDATE', 'DELETE', 'USAGE')
- `result` (TEXT): Whether permission is 'ALLOWED' or 'DENIED'
- `details` (TEXT): Descriptive details about what was tested

**Examples:**
```sql
-- Test current permissions
SELECT * FROM temp_mgmt.test_user_permissions('readonly_user');

-- Test permissions on specific schema
SELECT * FROM temp_mgmt.test_user_permissions('analyst_user', 'reporting');

-- Check only if user can write
SELECT * FROM temp_mgmt.test_user_permissions('readonly_user') 
WHERE operation IN ('WRITE', 'UPDATE', 'DELETE');
```

---

## Utility Functions

### `emergency_revoke_all_access()`

Immediately revokes all active temporary access grants (emergency use).

**Signature:**
```sql
temp_mgmt.emergency_revoke_all_access(
    target_schema TEXT DEFAULT NULL,       -- Optional: limit to specific schema
    reason TEXT DEFAULT 'Emergency revocation by administrator'
) RETURNS JSONB
```

### `cleanup_expired_grants()`

Maintenance function to clean up expired grants (runs automatically).

**Signature:**
```sql
temp_mgmt.cleanup_expired_grants() RETURNS JSONB
```

### `get_system_status()`

Returns comprehensive system status and statistics.

**Signature:**
```sql
temp_mgmt.get_system_status() RETURNS JSONB
```

**Returns:** JSONB object with system statistics
```json
{
  "current_time": "2024-03-15T11:30:00Z",
  "total_grants_ever": 156,
  "status_breakdown": {
    "active": 3,
    "revoked": 45,
    "expired": 98,
    "emergency_revoked": 10
  },
  "active_grants": {
    "count": 3,
    "next_expiry": "2024-03-15T12:15:00Z",
    "last_expiry": "2024-03-15T18:00:00Z"
  },
  "scheduled_cron_jobs": 3,
  "system_health": "OK"
}
```

---

## Error Codes and Handling

### Common Error Scenarios

1. **User Does Not Exist**
   ```json
   {"success": false, "error": "User nonexistent_user does not exist"}
   ```

2. **Schema Does Not Exist**
   ```json
   {"success": false, "error": "Schema nonexistent_schema does not exist"}
   ```

3. **Invalid Duration**
   ```json
   {"success": false, "error": "Duration must be between 1 and 168 hours (1 week max)"}
   ```

4. **Duplicate Grant**
   ```json
   {"success": false, "error": "User already has active temporary access"}
   ```

5. **No Active Grant Found**
   ```json
   {"success": false, "error": "No active grant found for user on schema"}
   ```

### Error Handling Best Practices

```sql
-- Always check the success field
DO $$
DECLARE
    result JSONB;
BEGIN
    SELECT temp_mgmt.grant_temporary_write_access('test_user') INTO result;
    
    IF (result->>'success')::BOOLEAN THEN
        RAISE NOTICE 'Success: %', result->>'message';
    ELSE
        RAISE WARNING 'Error: %', result->>'error';
    END IF;
END $$;
```

---

## Database Schema

### `temp_mgmt.temp_access_log` Table

Primary audit table for all temporary access operations.

```sql
CREATE TABLE temp_mgmt.temp_access_log (
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
```

**Indexes:**
- `idx_temp_access_username_status` - Query by user and status
- `idx_temp_access_schema_status` - Query by schema and status  
- `idx_temp_access_scheduled_revoke` - Query by expiration time

---

## Best Practices

### Function Usage
1. **Always use JSONB pretty printing** for readable output: `SELECT jsonb_pretty(...)`
2. **Check success field** before assuming operation succeeded
3. **Provide meaningful reasons** for audit trail
4. **Include emergency contacts** for high-privilege grants
5. **Use minimal necessary permissions** (UPDATE only vs full write access)

### Monitoring
1. **Regular status checks**: `SELECT temp_mgmt.get_system_status()`
2. **Active grant reviews**: `SELECT * FROM temp_mgmt.check_temporary_access()`  
3. **Permission verification**: `SELECT * FROM temp_mgmt.test_user_permissions(...)`

### Security
1. **Limit grant duration** to minimum necessary time
2. **Use emergency revoke** for security incidents
3. **Review audit logs** regularly
4. **Test permissions** before and after grants
5. **Monitor system health** for expired grants
