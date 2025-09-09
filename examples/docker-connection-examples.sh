#!/bin/bash

# PostgreSQL Temporary User Elevation - Docker Connection Examples
# This script shows how to connect to the PostgreSQL container and test functionality

set -e

echo "================================================"
echo "PostgreSQL Temporary User Elevation"
echo "Docker Connection Examples"
echo "================================================"
echo ""

# Container name (adjust if you changed it in docker-compose.yml)
CONTAINER_NAME="temp-elevation-postgres"
DB_NAME="testdb"

# Check if container is running
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    echo "❌ Container $CONTAINER_NAME is not running!"
    echo "Start it with: docker-compose up -d"
    exit 1
fi

echo "✅ Container $CONTAINER_NAME is running"
echo ""

# Function to run SQL as admin
run_as_admin() {
    echo "🔧 Running as admin:"
    echo "   $1"
    docker exec -i "$CONTAINER_NAME" psql -U admin -d "$DB_NAME" -c "$1"
    echo ""
}

# Function to run SQL file as admin
run_file_as_admin() {
    echo "🔧 Running file as admin: $1"
    docker exec -i "$CONTAINER_NAME" psql -U admin -d "$DB_NAME" < "$1"
    echo ""
}

# Function to run SQL as specific user
run_as_user() {
    local username=$1
    local password=$2
    local query=$3
    echo "👤 Running as $username:"
    echo "   $query"
    PGPASSWORD="$password" docker exec -i "$CONTAINER_NAME" psql -U "$username" -d "$DB_NAME" -c "$query"
    echo ""
}

echo "=== Example 1: System Status Check ==="
run_as_admin "SELECT jsonb_pretty(temp_mgmt.get_system_status());"

echo "=== Example 2: Test readonly_user Initial Permissions ==="
run_as_user "readonly_user" "readonly123" "SELECT * FROM temp_mgmt.test_user_permissions('readonly_user', 'app_data');"

echo "=== Example 3: Grant Temporary Access ==="
run_as_admin "
SELECT jsonb_pretty(
    temp_mgmt.grant_temporary_write_access(
        'readonly_user',
        'app_data',
        1,
        ARRAY['INSERT', 'UPDATE', 'DELETE'],
        'Docker test run - demonstrating functionality',
        'admin@example.com'
    )
);
"

echo "=== Example 4: Test readonly_user Permissions After Grant ==="
run_as_user "readonly_user" "readonly123" "SELECT * FROM temp_mgmt.test_user_permissions('readonly_user', 'app_data');"

echo "=== Example 5: Test Actual Write Operations ==="
echo "👤 Testing actual database operations as readonly_user:"

# Test INSERT
echo "Testing INSERT operation..."
PGPASSWORD="readonly123" docker exec -i "$CONTAINER_NAME" psql -U readonly_user -d "$DB_NAME" -c "
DO \$\$
DECLARE
    error_msg TEXT;
BEGIN
    BEGIN
        INSERT INTO app_data.users (name, email, department) 
        VALUES ('Docker Test User', 'docker_test@example.com', 'Testing');
        
        RAISE NOTICE 'INSERT successful! Write access is working.';
        
        -- Clean up immediately
        DELETE FROM app_data.users WHERE email = 'docker_test@example.com';
        RAISE NOTICE 'Test record cleaned up.';
        
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'INSERT failed: Insufficient privileges';
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_msg = MESSAGE_TEXT;
        RAISE NOTICE 'INSERT failed: %', error_msg;
    END;
END \$\$;
"

echo ""

echo "=== Example 6: Check Active Grants ==="
run_as_admin "
SELECT 
    username,
    target_schema,
    permissions_granted,
    granted_at,
    scheduled_revoke_at,
    ROUND(hours_remaining, 2) as hours_remaining,
    reason
FROM temp_mgmt.check_temporary_access()
WHERE status = 'active';
"

echo "=== Example 7: Manual Revoke (Optional) ==="
echo "💡 To manually revoke access, uncomment and run the following:"
echo "# run_as_admin \"SELECT jsonb_pretty(temp_mgmt.revoke_temporary_write_access('readonly_user', 'app_data'));\""
echo ""

echo "=== Example 8: Interactive Connection Examples ==="
echo ""
echo "To connect interactively to test different users:"
echo ""
echo "As admin:"
echo "  docker exec -it $CONTAINER_NAME psql -U admin -d $DB_NAME"
echo ""
echo "As readonly_user:"
echo "  docker exec -it $CONTAINER_NAME psql -U readonly_user -d $DB_NAME"
echo ""
echo "As readwrite_user:"
echo "  docker exec -it $CONTAINER_NAME psql -U readwrite_user -d $DB_NAME"
echo ""
echo "As analyst_user:"
echo "  docker exec -it $CONTAINER_NAME psql -U analyst_user -d $DB_NAME"
echo ""

echo "=== Example 9: Run Complete Test Suite ==="
echo ""
echo "To run the complete test suite:"
echo "  docker exec -i $CONTAINER_NAME psql -U admin -d $DB_NAME < test-scripts/main-test.sql"
echo ""
echo "To run user connection tests:"
echo "  PGPASSWORD=readonly123 docker exec -i $CONTAINER_NAME psql -U readonly_user -d $DB_NAME < test-scripts/user-connection-test.sql"
echo ""

echo "=== Example 10: Run Examples ==="
echo ""
echo "To run basic usage examples:"
echo "  docker exec -i $CONTAINER_NAME psql -U admin -d $DB_NAME < examples/basic-usage.sql"
echo ""
echo "To run real-world scenarios:"
echo "  docker exec -i $CONTAINER_NAME psql -U admin -d $DB_NAME < examples/real-world-scenarios.sql"
echo ""

echo "=== Example 11: Monitor Logs ==="
echo ""
echo "To monitor PostgreSQL logs:"
echo "  docker logs -f $CONTAINER_NAME"
echo ""

echo "=== Example 12: pgAdmin Access (if enabled) ==="
echo ""
echo "If you started with GUI profile, pgAdmin is available at:"
echo "  http://localhost:8080"
echo "  Email: admin@example.com"
echo "  Password: admin123"
echo ""
echo "To start with pgAdmin:"
echo "  docker-compose --profile gui up -d"
echo ""

echo "================================================"
echo "Docker Connection Examples Complete"
echo "================================================"
echo ""
echo "🔒 Security Notes:"
echo "- temporary access will expire automatically"
echo "- All operations are logged in temp_mgmt.temp_access_log"
echo "- Use emergency_revoke_all_access() for immediate revocation"
echo "- Monitor active grants with check_temporary_access()"

