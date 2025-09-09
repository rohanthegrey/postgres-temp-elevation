#!/bin/bash

# PostgreSQL Temporary User Elevation - Quick Start Script
# This script helps you get up and running quickly

set -e

echo "🚀 PostgreSQL Temporary User Elevation - Quick Start"
echo "===================================================="
echo ""

# Check if docker and docker-compose are installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    echo "   Visit: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ docker-compose is not installed. Please install docker-compose first."
    echo "   Visit: https://docs.docker.com/compose/install/"
    exit 1
fi

echo "✅ Docker and docker-compose are installed"
echo ""

# Start the containers
echo "🐳 Starting PostgreSQL container with pg_cron..."
docker-compose up -d

echo ""
echo "⏳ Waiting for PostgreSQL to be ready..."

# Wait for PostgreSQL to be ready
for i in {1..30}; do
    if docker exec temp-elevation-postgres pg_isready -U admin -d testdb &> /dev/null; then
        echo "✅ PostgreSQL is ready!"
        break
    fi
    
    if [ $i -eq 30 ]; then
        echo "❌ PostgreSQL failed to start after 30 seconds"
        echo "Check logs with: docker-compose logs postgres"
        exit 1
    fi
    
    sleep 1
done

echo ""
echo "🧪 Running basic functionality test..."

# Run a basic test
docker exec -i temp-elevation-postgres psql -U admin -d testdb -c "
SELECT 'System Status:' as test;
SELECT jsonb_pretty(temp_mgmt.get_system_status());
" 2>/dev/null || {
    echo "❌ Basic test failed. Check the setup."
    exit 1
}

echo ""
echo "🎉 Setup complete! Your PostgreSQL Temporary User Elevation system is ready."
echo ""
echo "📋 Quick Actions:"
echo ""
echo "1. Connect as admin:"
echo "   docker exec -it temp-elevation-postgres psql -U admin -d testdb"
echo ""
echo "2. Run comprehensive test suite:"
echo "   docker exec -i temp-elevation-postgres psql -U admin -d testdb < test-scripts/main-test.sql"
echo ""
echo "3. Test as readonly user:"
echo "   docker exec -it temp-elevation-postgres psql -U readonly_user -d testdb"
echo ""
echo "4. Run usage examples:"
echo "   docker exec -i temp-elevation-postgres psql -U admin -d testdb < examples/basic-usage.sql"
echo ""
echo "5. Access pgAdmin (if using --profile gui):"
echo "   http://localhost:8080 (admin@example.com / admin123)"
echo ""
echo "📚 Documentation:"
echo "   - README.md - Comprehensive documentation"
echo "   - docs/API.md - Complete API reference"
echo "   - examples/ - Usage examples and real-world scenarios"
echo ""
echo "🔧 Management Commands:"
echo "   - Start: docker-compose up -d"
echo "   - Stop: docker-compose down"
echo "   - Logs: docker-compose logs -f postgres"
echo "   - Reset: docker-compose down -v && docker-compose up -d"
echo ""
echo "Happy database management! 🎯"
