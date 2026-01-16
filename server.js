// Backend API for Warehouse Management System
// File: server.js

const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());

// Database connection
const pool = new Pool({
    user: 'postgres',
    host: 'db.hvtrgbzbwkiwkgbpbann.supabase.co',  // e.g., 'localhost' or Supabase URL
    database: 'postgres',
    password: 'OttoBismarck2025**',
    port: 5432,
});

// Test database connection
pool.query('SELECT NOW()', (err, res) => {
    if (err) {
        console.error('Database connection error:', err);
    } else {
        console.log('Database connected successfully');
    }
});

// ============ PRODUCTS API ============

// Get all products
app.get('/api/products', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT 
                p.*,
                COALESCE(SUM(i.quantity_on_hand), 0) as quantity,
                CASE 
                    WHEN COALESCE(SUM(i.quantity_on_hand), 0) = 0 THEN 'out-of-stock'
                    WHEN COALESCE(SUM(i.quantity_on_hand), 0) < p.reorder_level THEN 'low-stock'
                    WHEN COALESCE(SUM(i.quantity_on_hand), 0) < (p.reorder_level * 1.5) THEN 'critical'
                    ELSE 'in-stock'
                END as status
            FROM products p
            LEFT JOIN inventory i ON p.product_id = i.product_id
            WHERE p.is_active = true
            GROUP BY p.product_id
            ORDER BY p.product_name
        `);
        res.json(result.rows);
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Server error' });
    }
});

// Get single product
app.get('/api/products/:id', async (req, res) => {
    try {
        const { id } = req.params;
        const result = await pool.query(
            'SELECT * FROM products WHERE product_id = $1',
            [id]
        );
        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Product not found' });
        }
        res.json(result.rows[0]);
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Server error' });
    }
});

// Create product
app.post('/api/products', async (req, res) => {
    try {
        const { sku, product_name, description, category, supplier_id, unit_price, unit_cost, reorder_level, reorder_quantity } = req.body;
        
        const result = await pool.query(
            `INSERT INTO products (sku, product_name, description, category, supplier_id, unit_price, unit_cost, reorder_level, reorder_quantity)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
             RETURNING *`,
            [sku, product_name, description, category, supplier_id, unit_price, unit_cost, reorder_level, reorder_quantity]
        );
        res.status(201).json(result.rows[0]);
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Server error' });
    }
});

// Update product
app.put('/api/products/:id', async (req, res) => {
    try {
        const { id } = req.params;
        const { product_name, description, category, unit_price, unit_cost, reorder_level, reorder_quantity } = req.body;
        
        const result = await pool.query(
            `UPDATE products 
             SET product_name = $1, description = $2, category = $3, unit_price = $4, 
                 unit_cost = $5, reorder_level = $6, reorder_quantity = $7, updated_at = NOW()
             WHERE product_id = $8
             RETURNING *`,
            [product_name, description, category, unit_price, unit_cost, reorder_level, reorder_quantity, id]
        );
        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Product not found' });
        }
        res.json(result.rows[0]);
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Server error' });
    }
});

// Delete product (soft delete)
app.delete('/api/products/:id', async (req, res) => {
    try {
        const { id } = req.params;
        const result = await pool.query(
            'UPDATE products SET is_active = false WHERE product_id = $1 RETURNING *',
            [id]
        );
        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Product not found' });
        }
        res.json({ message: 'Product deleted successfully' });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Server error' });
    }
});

// ============ ORDERS API ============

// Get all orders
app.get('/api/orders', async (req, res) => {
    try {
        const { type, status } = req.query;
        let query = `
            SELECT 
                o.*,
                COALESCE(c.customer_name, s.supplier_name) as partner_name,
                COUNT(oi.order_item_id) as item_count,
                SUM(oi.quantity_ordered * oi.unit_price) as total_amount
            FROM orders o
            LEFT JOIN customers c ON o.customer_id = c.customer_id
            LEFT JOIN suppliers s ON o.supplier_id = s.supplier_id
            LEFT JOIN order_items oi ON o.order_id = oi.order_id
            WHERE 1=1
        `;
        const params = [];
        
        if (type) {
            params.push(type);
            query += ` AND o.order_type = $${params.length}`;
        }
        if (status) {
            params.push(status);
            query += ` AND o.status = $${params.length}`;
        }
        
        query += ' GROUP BY o.order_id, c.customer_name, s.supplier_name ORDER BY o.order_date DESC';
        
        const result = await pool.query(query, params);
        res.json(result.rows);
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Server error' });
    }
});

// Get single order with items
app.get('/api/orders/:id', async (req, res) => {
    try {
        const { id } = req.params;
        
        // Get order header
        const orderResult = await pool.query(
            `SELECT o.*, c.customer_name, s.supplier_name
             FROM orders o
             LEFT JOIN customers c ON o.customer_id = c.customer_id
             LEFT JOIN suppliers s ON o.supplier_id = s.supplier_id
             WHERE o.order_id = $1`,
            [id]
        );
        
        if (orderResult.rows.length === 0) {
            return res.status(404).json({ error: 'Order not found' });
        }
        
        // Get order items
        const itemsResult = await pool.query(
            `SELECT oi.*, p.product_name, p.sku
             FROM order_items oi
             JOIN products p ON oi.product_id = p.product_id
             WHERE oi.order_id = $1`,
            [id]
        );
        
        const order = orderResult.rows[0];
        order.items = itemsResult.rows;
        
        res.json(order);
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Server error' });
    }
});

// Create order
app.post('/api/orders', async (req, res) => {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        
        const { order_number, order_type, customer_id, supplier_id, warehouse_id, order_date, items } = req.body;
        
        // Insert order header
        const orderResult = await client.query(
            `INSERT INTO orders (order_number, order_type, customer_id, supplier_id, warehouse_id, order_date, status)
             VALUES ($1, $2, $3, $4, $5, $6, 'pending')
             RETURNING *`,
            [order_number, order_type, customer_id, supplier_id, warehouse_id, order_date]
        );
        
        const orderId = orderResult.rows[0].order_id;
        
        // Insert order items
        for (const item of items) {
            await client.query(
                `INSERT INTO order_items (order_id, product_id, quantity_ordered, unit_price)
                 VALUES ($1, $2, $3, $4)`,
                [orderId, item.product_id, item.quantity, item.unit_price]
            );
            
            // If outbound order, allocate inventory
            if (order_type === 'outbound') {
                await client.query(
                    `UPDATE inventory 
                     SET quantity_allocated = quantity_allocated + $1
                     WHERE product_id = $2 AND warehouse_id = $3`,
                    [item.quantity, item.product_id, warehouse_id]
                );
            }
        }
        
        await client.query('COMMIT');
        res.status(201).json(orderResult.rows[0]);
    } catch (err) {
        await client.query('ROLLBACK');
        console.error(err);
        res.status(500).json({ error: 'Server error' });
    } finally {
        client.release();
    }
});

// Update order status
app.patch('/api/orders/:id/status', async (req, res) => {
    try {
        const { id } = req.params;
        const { status } = req.body;
        
        const result = await pool.query(
            'UPDATE orders SET status = $1, updated_at = NOW() WHERE order_id = $2 RETURNING *',
            [status, id]
        );
        
        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Order not found' });
        }
        
        res.json(result.rows[0]);
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Server error' });
    }
});

// ============ INVENTORY API ============

// Get inventory levels
app.get('/api/inventory', async (req, res) => {
    try {
        const { warehouse_id, product_id } = req.query;
        let query = `
            SELECT 
                i.*,
                p.product_name,
                p.sku,
                l.location_code,
                w.warehouse_name
            FROM inventory i
            JOIN products p ON i.product_id = p.product_id
            JOIN locations l ON i.location_id = l.location_id
            JOIN warehouses w ON i.warehouse_id = w.warehouse_id
            WHERE 1=1
        `;
        const params = [];
        
        if (warehouse_id) {
            params.push(warehouse_id);
            query += ` AND i.warehouse_id = $${params.length}`;
        }
        if (product_id) {
            params.push(product_id);
            query += ` AND i.product_id = $${params.length}`;
        }
        
        const result = await pool.query(query, params);
        res.json(result.rows);
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Server error' });
    }
});

// Adjust inventory
app.post('/api/inventory/adjust', async (req, res) => {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        
        const { product_id, location_id, warehouse_id, quantity_change, reason, user_id } = req.body;
        
        // Get current quantity
        const currentResult = await client.query(
            'SELECT quantity_on_hand FROM inventory WHERE product_id = $1 AND location_id = $2',
            [product_id, location_id]
        );
        
        const currentQty = currentResult.rows[0]?.quantity_on_hand || 0;
        const newQty = currentQty + quantity_change;
        
        // Update or insert inventory
        await client.query(
            `INSERT INTO inventory (product_id, location_id, warehouse_id, quantity_on_hand, last_movement_date)
             VALUES ($1, $2, $3, $4, NOW())
             ON CONFLICT (product_id, location_id, lot_number)
             DO UPDATE SET 
                quantity_on_hand = $4,
                last_movement_date = NOW()`,
            [product_id, location_id, warehouse_id, newQty]
        );
        
        // Record transaction
        await client.query(
            `INSERT INTO inventory_transactions 
             (product_id, location_id, warehouse_id, transaction_type, quantity_change, quantity_before, quantity_after, reason, performed_by)
             VALUES ($1, $2, $3, 'adjustment', $4, $5, $6, $7, $8)`,
            [product_id, location_id, warehouse_id, quantity_change, currentQty, newQty, reason, user_id]
        );
        
        await client.query('COMMIT');
        res.json({ message: 'Inventory adjusted successfully', new_quantity: newQty });
    } catch (err) {
        await client.query('ROLLBACK');
        console.error(err);
        res.status(500).json({ error: 'Server error' });
    } finally {
        client.release();
    }
});

// ============ DASHBOARD API ============

// Get dashboard statistics
app.get('/api/dashboard/stats', async (req, res) => {
    try {
        // Total products
        const productsResult = await pool.query('SELECT COUNT(*) FROM products WHERE is_active = true');
        
        // Total orders today
        const ordersResult = await pool.query(
            "SELECT COUNT(*) FROM orders WHERE order_date = CURRENT_DATE"
        );
        
        // Low stock items
        const lowStockResult = await pool.query(`
            SELECT COUNT(DISTINCT p.product_id)
            FROM products p
            LEFT JOIN inventory i ON p.product_id = i.product_id
            GROUP BY p.product_id
            HAVING COALESCE(SUM(i.quantity_on_hand), 0) < p.reorder_level
        `);
        
        // Total inventory value
        const valueResult = await pool.query(`
            SELECT SUM(i.quantity_on_hand * p.unit_cost) as total_value
            FROM inventory i
            JOIN products p ON i.product_id = p.product_id
        `);
        
        res.json({
            totalProducts: parseInt(productsResult.rows[0].count),
            ordersToday: parseInt(ordersResult.rows[0].count),
            lowStockItems: parseInt(lowStockResult.rows[0].count),
            totalValue: parseFloat(valueResult.rows[0].total_value || 0)
        });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Server error' });
    }
});

// ============ LOCATIONS API ============

// Get all locations
app.get('/api/locations', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT 
                l.*,
                z.zone_name,
                w.warehouse_name,
                i.product_id,
                p.product_name,
                i.quantity_on_hand
            FROM locations l
            JOIN zones z ON l.zone_id = z.zone_id
            JOIN warehouses w ON z.warehouse_id = w.warehouse_id
            LEFT JOIN inventory i ON l.location_id = i.location_id
            LEFT JOIN products p ON i.product_id = p.product_id
            WHERE l.is_active = true
            ORDER BY w.warehouse_name, z.zone_name, l.location_code
        `);
        res.json(result.rows);
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Server error' });
    }
});

// ============ WAREHOUSES API ============

// Get all warehouses
app.get('/api/warehouses', async (req, res) => {
    try {
        const result = await pool.query(
            'SELECT * FROM warehouses WHERE is_active = true ORDER BY warehouse_name'
        );
        res.json(result.rows);
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Server error' });
    }
});

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({ status: 'ok', message: 'Warehouse Management API is running' });
});

// Start server
app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
    console.log(`API available at http://localhost:${PORT}/api`);
});

// Error handling
process.on('unhandledRejection', (err) => {
    console.error('Unhandled rejection:', err);
});
