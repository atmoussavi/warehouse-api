-- Warehouse Management System Database Schema
-- PostgreSQL/MySQL compatible

-- Drop existing tables (in reverse dependency order)
DROP TABLE IF EXISTS inventory_transactions;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS inventory;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS locations;
DROP TABLE IF EXISTS zones;
DROP TABLE IF EXISTS warehouses;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS suppliers;
DROP TABLE IF EXISTS users;

-- Users table (warehouse staff, managers, etc.)
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    role VARCHAR(20) CHECK (role IN ('admin', 'manager', 'warehouse_staff', 'viewer')),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Warehouses table
CREATE TABLE warehouses (
    warehouse_id SERIAL PRIMARY KEY,
    warehouse_code VARCHAR(20) UNIQUE NOT NULL,
    warehouse_name VARCHAR(100) NOT NULL,
    address TEXT,
    city VARCHAR(50),
    state VARCHAR(50),
    country VARCHAR(50),
    postal_code VARCHAR(20),
    phone VARCHAR(20),
    email VARCHAR(100),
    manager_id INTEGER REFERENCES users(user_id),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Zones table (areas within warehouses)
CREATE TABLE zones (
    zone_id SERIAL PRIMARY KEY,
    warehouse_id INTEGER REFERENCES warehouses(warehouse_id) ON DELETE CASCADE,
    zone_code VARCHAR(20) NOT NULL,
    zone_name VARCHAR(100),
    zone_type VARCHAR(30) CHECK (zone_type IN ('receiving', 'storage', 'picking', 'packing', 'shipping', 'returns')),
    capacity INTEGER,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(warehouse_id, zone_code)
);

-- Locations table (specific storage positions)
CREATE TABLE locations (
    location_id SERIAL PRIMARY KEY,
    zone_id INTEGER REFERENCES zones(zone_id) ON DELETE CASCADE,
    location_code VARCHAR(50) NOT NULL,
    aisle VARCHAR(10),
    rack VARCHAR(10),
    shelf VARCHAR(10),
    bin VARCHAR(10),
    location_type VARCHAR(20) CHECK (location_type IN ('rack', 'floor', 'bulk', 'pallet')),
    capacity_cubic_ft DECIMAL(10,2),
    max_weight_lbs DECIMAL(10,2),
    is_occupied BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(zone_id, location_code)
);

-- Suppliers table
CREATE TABLE suppliers (
    supplier_id SERIAL PRIMARY KEY,
    supplier_code VARCHAR(20) UNIQUE NOT NULL,
    supplier_name VARCHAR(100) NOT NULL,
    contact_person VARCHAR(100),
    email VARCHAR(100),
    phone VARCHAR(20),
    address TEXT,
    city VARCHAR(50),
    state VARCHAR(50),
    country VARCHAR(50),
    postal_code VARCHAR(20),
    payment_terms VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Customers table
CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    customer_code VARCHAR(20) UNIQUE NOT NULL,
    customer_name VARCHAR(100) NOT NULL,
    contact_person VARCHAR(100),
    email VARCHAR(100),
    phone VARCHAR(20),
    billing_address TEXT,
    shipping_address TEXT,
    city VARCHAR(50),
    state VARCHAR(50),
    country VARCHAR(50),
    postal_code VARCHAR(20),
    customer_type VARCHAR(20) CHECK (customer_type IN ('retail', 'wholesale', 'distributor')),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Products table
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    sku VARCHAR(50) UNIQUE NOT NULL,
    product_name VARCHAR(200) NOT NULL,
    description TEXT,
    category VARCHAR(50),
    supplier_id INTEGER REFERENCES suppliers(supplier_id),
    unit_of_measure VARCHAR(20) DEFAULT 'each',
    unit_price DECIMAL(10,2),
    unit_cost DECIMAL(10,2),
    weight_lbs DECIMAL(10,2),
    dimensions_inches VARCHAR(50), -- format: "L x W x H"
    reorder_level INTEGER DEFAULT 0,
    reorder_quantity INTEGER DEFAULT 0,
    barcode VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Inventory table (tracks stock at location level)
CREATE TABLE inventory (
    inventory_id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES products(product_id) ON DELETE CASCADE,
    location_id INTEGER REFERENCES locations(location_id) ON DELETE CASCADE,
    warehouse_id INTEGER REFERENCES warehouses(warehouse_id) ON DELETE CASCADE,
    quantity_on_hand INTEGER DEFAULT 0,
    quantity_allocated INTEGER DEFAULT 0, -- reserved for orders
    quantity_available INTEGER GENERATED ALWAYS AS (quantity_on_hand - quantity_allocated) STORED,
    lot_number VARCHAR(50),
    expiry_date DATE,
    last_counted_date DATE,
    last_movement_date TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(product_id, location_id, lot_number)
);

-- Orders table
CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    order_number VARCHAR(50) UNIQUE NOT NULL,
    order_type VARCHAR(20) CHECK (order_type IN ('inbound', 'outbound', 'transfer', 'adjustment')) NOT NULL,
    customer_id INTEGER REFERENCES customers(customer_id),
    supplier_id INTEGER REFERENCES suppliers(supplier_id),
    warehouse_id INTEGER REFERENCES warehouses(warehouse_id) NOT NULL,
    order_date DATE NOT NULL,
    expected_date DATE,
    completed_date DATE,
    status VARCHAR(20) CHECK (status IN ('pending', 'processing', 'picked', 'packed', 'shipped', 'delivered', 'cancelled')) DEFAULT 'pending',
    priority VARCHAR(10) CHECK (priority IN ('low', 'medium', 'high', 'urgent')) DEFAULT 'medium',
    shipping_address TEXT,
    tracking_number VARCHAR(100),
    notes TEXT,
    created_by INTEGER REFERENCES users(user_id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Order Items table
CREATE TABLE order_items (
    order_item_id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES orders(order_id) ON DELETE CASCADE,
    product_id INTEGER REFERENCES products(product_id),
    location_id INTEGER REFERENCES locations(location_id),
    quantity_ordered INTEGER NOT NULL,
    quantity_picked INTEGER DEFAULT 0,
    quantity_packed INTEGER DEFAULT 0,
    quantity_shipped INTEGER DEFAULT 0,
    unit_price DECIMAL(10,2),
    lot_number VARCHAR(50),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Inventory Transactions table (audit trail)
CREATE TABLE inventory_transactions (
    transaction_id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES products(product_id),
    location_id INTEGER REFERENCES locations(location_id),
    warehouse_id INTEGER REFERENCES warehouses(warehouse_id),
    order_id INTEGER REFERENCES orders(order_id),
    transaction_type VARCHAR(30) CHECK (transaction_type IN ('receipt', 'pick', 'adjustment', 'transfer', 'return', 'cycle_count')) NOT NULL,
    quantity_change INTEGER NOT NULL, -- positive for increases, negative for decreases
    quantity_before INTEGER,
    quantity_after INTEGER,
    lot_number VARCHAR(50),
    reason VARCHAR(100),
    performed_by INTEGER REFERENCES users(user_id),
    transaction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes TEXT
);

-- Indexes for better query performance
CREATE INDEX idx_inventory_product ON inventory(product_id);
CREATE INDEX idx_inventory_location ON inventory(location_id);
CREATE INDEX idx_inventory_warehouse ON inventory(warehouse_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_type ON orders(order_type);
CREATE INDEX idx_orders_date ON orders(order_date);
CREATE INDEX idx_transactions_product ON inventory_transactions(product_id);
CREATE INDEX idx_transactions_date ON inventory_transactions(transaction_date);
CREATE INDEX idx_products_sku ON products(sku);
CREATE INDEX idx_locations_zone ON locations(zone_id);

-- Sample data for testing
INSERT INTO users (username, email, password_hash, first_name, last_name, role) VALUES
('admin', 'admin@warehouse.com', 'hashed_password_here', 'Admin', 'User', 'admin'),
('jsmith', 'john.smith@warehouse.com', 'hashed_password_here', 'John', 'Smith', 'manager'),
('mjones', 'mary.jones@warehouse.com', 'hashed_password_here', 'Mary', 'Jones', 'warehouse_staff');

INSERT INTO warehouses (warehouse_code, warehouse_name, address, city, state, country, postal_code, manager_id) VALUES
('WH001', 'Main Distribution Center', '123 Warehouse Blvd', 'Chicago', 'IL', 'USA', '60601', 2),
('WH002', 'East Coast Facility', '456 Shipping Lane', 'Newark', 'NJ', 'USA', '07102', 2);

INSERT INTO zones (warehouse_id, zone_code, zone_name, zone_type, capacity) VALUES
(1, 'Z-RCV', 'Receiving Dock', 'receiving', 1000),
(1, 'Z-A01', 'Storage Zone A', 'storage', 5000),
(1, 'Z-B01', 'Storage Zone B', 'storage', 5000),
(1, 'Z-PCK', 'Packing Area', 'packing', 500),
(1, 'Z-SHP', 'Shipping Dock', 'shipping', 1000);

INSERT INTO locations (zone_id, location_code, aisle, rack, shelf, bin, location_type, capacity_cubic_ft, max_weight_lbs) VALUES
(2, 'A01-R01-S01-B01', 'A01', 'R01', 'S01', 'B01', 'rack', 10.5, 100),
(2, 'A01-R01-S01-B02', 'A01', 'R01', 'S01', 'B02', 'rack', 10.5, 100),
(2, 'A01-R01-S02-B01', 'A01', 'R01', 'S02', 'B01', 'rack', 10.5, 100),
(3, 'B01-FL-001', 'B01', NULL, NULL, NULL, 'floor', 100, 2000);

INSERT INTO suppliers (supplier_code, supplier_name, contact_person, email, phone, country) VALUES
('SUP001', 'Acme Manufacturing', 'Bob Wilson', 'bob@acme.com', '555-0100', 'USA'),
('SUP002', 'Global Imports Inc', 'Sarah Chen', 'sarah@globalimports.com', '555-0200', 'China');

INSERT INTO customers (customer_code, customer_name, contact_person, email, phone, customer_type) VALUES
('CUST001', 'Retail Giants LLC', 'Tom Anderson', 'tom@retailgiants.com', '555-1000', 'wholesale'),
('CUST002', 'Online Marketplace Co', 'Lisa Martinez', 'lisa@onlinemarketplace.com', '555-2000', 'retail');

INSERT INTO products (sku, product_name, description, category, supplier_id, unit_price, unit_cost, reorder_level, reorder_quantity, barcode) VALUES
('PROD-001', 'Widget A', 'Standard widget, blue', 'Widgets', 1, 29.99, 15.00, 100, 500, '1234567890123'),
('PROD-002', 'Widget B', 'Deluxe widget, red', 'Widgets', 1, 49.99, 25.00, 50, 250, '1234567890124'),
('PROD-003', 'Gadget X', 'Electronic gadget', 'Electronics', 2, 199.99, 120.00, 25, 100, '1234567890125');

-- Comments documenting the schema
COMMENT ON TABLE warehouses IS 'Physical warehouse locations';
COMMENT ON TABLE zones IS 'Logical zones within warehouses for organizing inventory';
COMMENT ON TABLE locations IS 'Specific storage locations within zones';
COMMENT ON TABLE inventory IS 'Current inventory levels at each location';
COMMENT ON TABLE orders IS 'All types of orders: inbound receipts, outbound shipments, transfers, adjustments';
COMMENT ON TABLE inventory_transactions IS 'Complete audit trail of all inventory movements';
