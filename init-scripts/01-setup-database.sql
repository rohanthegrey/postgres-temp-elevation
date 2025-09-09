-- PostgreSQL Temporary User Elevation - Database Setup
-- This script sets up the initial database structure and users

-- Create pg_cron extension for scheduling
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Grant cron usage to admin (optional, admin already has superuser)
-- GRANT USAGE ON SCHEMA cron TO admin;

-- Create test users with different permission levels
DO $$
BEGIN
    -- Create readonly user if doesn't exist
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'readonly_user') THEN
        CREATE USER readonly_user WITH PASSWORD 'readonly123';
    END IF;

    -- Create readwrite user if doesn't exist
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'readwrite_user') THEN
        CREATE USER readwrite_user WITH PASSWORD 'readwrite123';
    END IF;

    -- Create analyst user for testing
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'analyst_user') THEN
        CREATE USER analyst_user WITH PASSWORD 'analyst123';
    END IF;
END
$$;

-- Create application schemas
CREATE SCHEMA IF NOT EXISTS app_data;
CREATE SCHEMA IF NOT EXISTS reporting;
CREATE SCHEMA IF NOT EXISTS temp_mgmt;

-- Create sample tables in app_data schema
CREATE TABLE IF NOT EXISTS app_data.users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    department VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS app_data.orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES app_data.users(id),
    amount DECIMAL(10,2) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    order_date DATE DEFAULT CURRENT_DATE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS app_data.products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    category VARCHAR(100),
    price DECIMAL(10,2) NOT NULL,
    stock_quantity INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS app_data.order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES app_data.orders(id),
    product_id INTEGER REFERENCES app_data.products(id),
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    total_price DECIMAL(10,2) GENERATED ALWAYS AS (quantity * unit_price) STORED
);

-- Create reporting views
CREATE OR REPLACE VIEW reporting.user_order_summary AS
SELECT
    u.id,
    u.name,
    u.email,
    u.department,
    COUNT(o.id) as total_orders,
    COALESCE(SUM(o.amount), 0) as total_spent,
    MAX(o.created_at) as last_order_date
FROM app_data.users u
LEFT JOIN app_data.orders o ON u.id = o.user_id
GROUP BY u.id, u.name, u.email, u.department;

CREATE OR REPLACE VIEW reporting.product_sales AS
SELECT
    p.id,
    p.name,
    p.category,
    p.price,
    COALESCE(SUM(oi.quantity), 0) as total_sold,
    COALESCE(SUM(oi.total_price), 0) as total_revenue
FROM app_data.products p
LEFT JOIN app_data.order_items oi ON p.id = oi.product_id
GROUP BY p.id, p.name, p.category, p.price;

-- Insert sample data
INSERT INTO app_data.users (name, email, department) VALUES
    ('John Doe', 'john.doe@example.com', 'Engineering'),
    ('Jane Smith', 'jane.smith@example.com', 'Marketing'),
    ('Bob Johnson', 'bob.johnson@example.com', 'Sales'),
    ('Alice Brown', 'alice.brown@example.com', 'Engineering'),
    ('Charlie Wilson', 'charlie.wilson@example.com', 'Support')
ON CONFLICT (email) DO NOTHING;

INSERT INTO app_data.products (name, category, price, stock_quantity) VALUES
    ('Laptop Pro 15"', 'Electronics', 1299.99, 50),
    ('Wireless Mouse', 'Electronics', 29.99, 200),
    ('Standing Desk', 'Furniture', 299.99, 25),
    ('Office Chair', 'Furniture', 199.99, 30),
    ('Monitor 24"', 'Electronics', 179.99, 75)
ON CONFLICT DO NOTHING;

INSERT INTO app_data.orders (user_id, amount, status) VALUES
    (1, 1329.98, 'completed'),
    (2, 479.98, 'completed'),
    (3, 29.99, 'pending'),
    (1, 199.99, 'completed'),
    (4, 1299.99, 'processing')
ON CONFLICT DO NOTHING;

INSERT INTO app_data.order_items (order_id, product_id, quantity, unit_price) VALUES
    (1, 1, 1, 1299.99),
    (1, 2, 1, 29.99),
    (2, 3, 1, 299.99),
    (2, 4, 1, 199.99),
    (3, 2, 1, 29.99),
    (4, 4, 1, 199.99),
    (5, 1, 1, 1299.99)
ON CONFLICT DO NOTHING;

-- Grant initial permissions

-- readonly_user: SELECT only on app_data and reporting
GRANT USAGE ON SCHEMA app_data TO readonly_user;
GRANT USAGE ON SCHEMA reporting TO readonly_user;
GRANT SELECT ON ALL TABLES IN SCHEMA app_data TO readonly_user;
GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO readonly_user;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA app_data TO readonly_user;

-- Default permissions for future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA app_data
    GRANT SELECT ON TABLES TO readonly_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA reporting
    GRANT SELECT ON TABLES TO readonly_user;

-- readwrite_user: Full access to app_data
GRANT USAGE ON SCHEMA app_data TO readwrite_user;
GRANT USAGE ON SCHEMA reporting TO readwrite_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app_data TO readwrite_user;
GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO readwrite_user;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA app_data TO readwrite_user;

-- Default permissions for future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA app_data
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO readwrite_user;

-- analyst_user: SELECT only initially
GRANT USAGE ON SCHEMA app_data TO analyst_user;
GRANT USAGE ON SCHEMA reporting TO analyst_user;
GRANT SELECT ON ALL TABLES IN SCHEMA app_data TO analyst_user;
GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO analyst_user;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA app_data TO analyst_user;

-- Create a schema for temporary elevation management
GRANT USAGE ON SCHEMA temp_mgmt TO admin;
GRANT CREATE ON SCHEMA temp_mgmt TO admin;

-- Log setup completion
DO $$
BEGIN
    RAISE NOTICE 'Database setup completed successfully!';
    RAISE NOTICE 'Created users: readonly_user, readwrite_user, analyst_user';
    RAISE NOTICE 'Created schemas: app_data, reporting, temp_mgmt';
    RAISE NOTICE 'Sample data inserted into tables';
    RAISE NOTICE 'Initial permissions configured';
END $$;
