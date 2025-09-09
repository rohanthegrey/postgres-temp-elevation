# PostgreSQL Temporary User Elevation

A comprehensive Docker-based solution for granting time-bound write access to read-only database users with automatic revocation and comprehensive audit logging.

## 🔥 Key Features

- **🕐 Time-bound Access**: Automatically grant and revoke database permissions after specified duration
- **📊 Comprehensive Audit Trail**: Complete logging of all grants, revocations, and usage
- **🚨 Emergency Controls**: Instant revocation capabilities for security incidents
- **🔧 Flexible Permissions**: Granular control over which operations to grant (INSERT, UPDATE, DELETE)
- **📋 Rich Monitoring**: Real-time status checks, permission testing, and usage statistics
- **🐳 Docker Ready**: Complete containerized setup with PostgreSQL + pg_cron
- **🛡️ Security First**: Built-in safeguards, validation, and compliance features

## 🚀 Quick Start

### 1. Clone and Start

```bash
git clone <your-repo-url>
cd postgres-temp-elevation
docker-compose up -d
```

### 2. Verify Setup

```bash
# Check container status
docker-compose ps

# Run the main test suite
docker exec -i temp-elevation-postgres psql -U admin -d testdb < test-scripts/main-test.sql
```

### 3. Basic Usage

```bash
# Connect as admin
docker exec -it temp-elevation-postgres psql -U admin -d testdb

# Grant temporary write access
SELECT jsonb_pretty(
    temp_mgmt.grant_temporary_write_access(
        'readonly_user',     -- Target user
        'app_data',         -- Schema
        2,                  -- Hours
        ARRAY['INSERT', 'UPDATE', 'DELETE'],
        'Data fix task #123',
        'admin@company.com'
    )
);

# Check active grants
SELECT * FROM temp_mgmt.check_temporary_access();
```

## 📁 Project Structure

```
postgres-temp-elevation/
├── docker-compose.yml              # Docker setup with PostgreSQL + pg_cron
├── init-scripts/                   # Database initialization
│   ├── 01-setup-database.sql      # Users, schemas, sample data
│   ├── 02-temp-elevation-functions.sql  # Core elevation functions
│   └── 03-utility-functions.sql   # Additional utilities
├── test-scripts/                   # Test suites
│   ├── main-test.sql              # Comprehensive test suite
│   └── user-connection-test.sql   # User-specific testing
├── examples/                       # Usage examples
│   ├── basic-usage.sql            # Basic function examples
│   ├── real-world-scenarios.sql   # Real-world use cases
│   └── docker-connection-examples.sh  # Docker connection guide
├── docs/                          # Documentation
└── README.md                      # This file
```

## 🛠️ Core Functions

### Grant Access
```sql
temp_mgmt.grant_temporary_write_access(
    target_user TEXT,              -- Database user to grant access
    target_schema TEXT,            -- Schema to grant access on
    duration_hours INTEGER,        -- How long access should last
    permissions TEXT[],            -- Array of permissions to grant
    reason TEXT,                   -- Why access is needed
    emergency_contact TEXT         -- Who to contact if issues arise
)
```

### Check Access
```sql
temp_mgmt.check_temporary_access(
    filter_user TEXT,              -- Filter by specific user
    filter_schema TEXT,            -- Filter by specific schema  
    include_expired BOOLEAN        -- Include expired grants
)
```

### Revoke Access
```sql
temp_mgmt.revoke_temporary_write_access(
    target_user TEXT,              -- User to revoke access from
    target_schema TEXT             -- Schema to revoke access on
)
```

### Test Permissions
```sql
temp_mgmt.test_user_permissions(
    target_user TEXT,              -- User to test
    target_schema TEXT             -- Schema to test on
)
```

## 🔒 Security Features

### Built-in Safeguards
- **Duration Limits**: Maximum 168 hours (1 week) per grant
- **User Validation**: Ensures target users exist before granting access
- **Schema Validation**: Verifies target schemas exist
- **Duplicate Prevention**: Prevents multiple active grants for same user/schema
- **Automatic Cleanup**: Hourly job removes expired grants

### Audit Trail
Every operation is logged in `temp_mgmt.temp_access_log`:
- Who granted/revoked access
- When access was granted/revoked
- Why access was needed
- What permissions were granted
- Emergency contact information

### Emergency Controls
```sql
-- Immediate revocation of all active grants
SELECT temp_mgmt.emergency_revoke_all_access();

-- System status and health check
SELECT temp_mgmt.get_system_status();
```

## 📊 Monitoring & Reporting

### Active Grants Dashboard
```sql
SELECT 
    username,
    target_schema,
    permissions_granted,
    granted_at,
    scheduled_revoke_at,
    ROUND(hours_remaining, 2) as hours_left,
    reason,
    emergency_contact
FROM temp_mgmt.check_temporary_access()
WHERE status = 'active'
ORDER BY hours_remaining;
```

### Usage Statistics
```sql
-- Last 7 days summary
SELECT 
    DATE(granted_at) as date,
    COUNT(*) as total_grants,
    COUNT(*) FILTER (WHERE status = 'expired') as auto_expired,
    COUNT(*) FILTER (WHERE status = 'revoked') as manually_revoked,
    AVG(EXTRACT(EPOCH FROM COALESCE(revoked_at, scheduled_revoke_at) - granted_at)/3600) as avg_duration_hours
FROM temp_mgmt.temp_access_log
WHERE granted_at >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY DATE(granted_at)
ORDER BY date DESC;
```

## 🎯 Real-World Use Cases

### Data Analyst Temporary Access
```sql
SELECT temp_mgmt.grant_temporary_write_access(
    'analyst_user',
    'app_data', 
    4,
    ARRAY['UPDATE'],  -- Only UPDATE needed
    'Fix data quality issues in customer records - Ticket QA-001',
    'data-team@company.com'
);
```

### Emergency Data Fix
```sql
SELECT temp_mgmt.grant_temporary_write_access(
    'support_user',
    'app_data',
    1,  -- Quick 1-hour fix
    ARRAY['UPDATE'],
    'URGENT: Fix billing data affecting customers - INC-456',
    'support-manager@company.com'
);
```

### Scheduled Maintenance Window
```sql
SELECT temp_mgmt.grant_temporary_write_access(
    'maintenance_user',
    'app_data',
    8,  -- 8-hour maintenance window
    ARRAY['INSERT', 'UPDATE', 'DELETE'],
    'Weekly maintenance window - MAINT-2024-W42',
    'ops-team@company.com'
);
```

## 🧪 Testing

### Run Complete Test Suite
```bash
# Main comprehensive test
docker exec -i temp-elevation-postgres psql -U admin -d testdb < test-scripts/main-test.sql

# User-specific permission tests
PGPASSWORD=readonly123 docker exec -i temp-elevation-postgres psql -U readonly_user -d testdb < test-scripts/user-connection-test.sql

# Basic usage examples
docker exec -i temp-elevation-postgres psql -U admin -d testdb < examples/basic-usage.sql

# Real-world scenarios
docker exec -i temp-elevation-postgres psql -U admin -d testdb < examples/real-world-scenarios.sql
```

### Interactive Testing
```bash
# Connect as admin
docker exec -it temp-elevation-postgres psql -U admin -d testdb

# Connect as readonly user to test their permissions
docker exec -it temp-elevation-postgres psql -U readonly_user -d testdb

# Run Docker connection examples (guided testing)
./examples/docker-connection-examples.sh
```

## ⚙️ Configuration

### Default Users Created
- **admin** (password: admin123) - Full administrative access
- **readonly_user** (password: readonly123) - Read-only access initially
- **readwrite_user** (password: readwrite123) - Full write access
- **analyst_user** (password: analyst123) - Read-only access initially

### Default Schemas
- **app_data** - Main application data (users, orders, products)
- **reporting** - Read-only reporting views
- **temp_mgmt** - Temporary access management system

### Environment Variables
```yaml
# In docker-compose.yml
POSTGRES_DB: testdb
POSTGRES_USER: admin  
POSTGRES_PASSWORD: admin123
```

## 🔧 Advanced Features

### Extend Existing Access
```sql
SELECT temp_mgmt.extend_temporary_access(
    'readonly_user',
    'app_data', 
    2  -- Extend by 2 more hours
);
```

### Custom Permission Sets
```sql
-- Grant only INSERT and UPDATE, no DELETE
SELECT temp_mgmt.grant_temporary_write_access(
    'data_entry_user',
    'app_data',
    4,
    ARRAY['INSERT', 'UPDATE'],  -- Custom permission set
    'Data entry task - no deletion allowed',
    'supervisor@company.com'
);
```

### Schema-Specific Grants
```sql
-- Grant access only to reporting schema
SELECT temp_mgmt.grant_temporary_write_access(
    'analyst_user',
    'reporting',  -- Different schema
    6,
    ARRAY['INSERT', 'UPDATE'],
    'Update reporting configuration',
    'analytics-lead@company.com'
);
```

## 🚨 Emergency Procedures

### Security Incident Response
1. **Immediate Revocation**:
   ```sql
   SELECT temp_mgmt.emergency_revoke_all_access(NULL, 'Security incident INC-001');
   ```

2. **Assessment**:
   ```sql
   SELECT temp_mgmt.get_system_status();
   SELECT * FROM temp_mgmt.check_temporary_access(NULL, NULL, true);
   ```

3. **Audit Review**:
   ```sql
   SELECT * FROM temp_mgmt.temp_access_log 
   WHERE granted_at >= CURRENT_DATE - INTERVAL '24 hours'
   ORDER BY granted_at DESC;
   ```

### System Maintenance
```sql
-- Clean up old expired grants (runs automatically every hour)
SELECT temp_mgmt.cleanup_expired_grants();

-- Check system health
SELECT temp_mgmt.get_system_status();

-- Verify cron jobs are running
SELECT jobname, schedule, command FROM cron.job WHERE jobname LIKE 'revoke_%';
```

## 📈 Monitoring Best Practices

1. **Regular Health Checks**: Monitor `get_system_status()` output
2. **Active Grant Reviews**: Check `check_temporary_access()` regularly
3. **Audit Log Analysis**: Review access patterns in `temp_access_log`
4. **Alert Setup**: Configure alerts for long-running grants
5. **Emergency Contacts**: Ensure all grants have valid emergency contacts

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Test thoroughly using provided test scripts
4. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For issues, questions, or contributions:
- Create an issue on GitHub
- Check the `examples/` directory for usage patterns
- Run the test scripts to understand functionality
- Review the `docs/` directory for additional documentation

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Docker Host   │    │  PostgreSQL +    │    │   pg_cron       │
│                 │───▶│  temp_mgmt       │───▶│   Scheduler     │
│ (Your Machine)  │    │  Functions       │    │   (Auto-Revoke) │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌──────────────────┐
                       │  Audit Trail     │
                       │ temp_access_log  │
                       │                  │
                       └──────────────────┘
```

Built with ❤️ for secure, auditable database access management.
