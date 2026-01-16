-- Stored procedure to transfer inventory between locations
-- PostgreSQL PL/pgSQL function
-- Usage: psql -d yourdb -f db/stored_procedures/move_inventory.sql

CREATE OR REPLACE FUNCTION move_inventory(
    p_product_id INTEGER,
    p_from_location_id INTEGER,
    p_to_location_id INTEGER,
    p_quantity INTEGER,
    p_lot_number VARCHAR DEFAULT NULL,
    p_performed_by INTEGER DEFAULT NULL,
    p_reason VARCHAR DEFAULT 'transfer'
) RETURNS VOID AS $$
DECLARE
    v_src_inventory_id INTEGER;
    v_dest_inventory_id INTEGER;
    v_src_qoh INTEGER;
    v_dest_qoh INTEGER;
    v_src_warehouse_id INTEGER;
    v_dest_warehouse_id INTEGER;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Quantity must be a positive integer';
    END IF;

    IF p_from_location_id = p_to_location_id THEN
        RAISE EXCEPTION 'Source and destination locations are the same';
    END IF;

    -- Determine warehouse ids for source and destination (via zones)
    SELECT z.warehouse_id INTO v_src_warehouse_id
    FROM locations l JOIN zones z ON l.zone_id = z.zone_id
    WHERE l.location_id = p_from_location_id;

    SELECT z.warehouse_id INTO v_dest_warehouse_id
    FROM locations l JOIN zones z ON l.zone_id = z.zone_id
    WHERE l.location_id = p_to_location_id;

    -- Lock source inventory row (if exists)
    SELECT inventory_id, quantity_on_hand INTO v_src_inventory_id, v_src_qoh
    FROM inventory
    WHERE product_id = p_product_id
      AND location_id = p_from_location_id
      AND (lot_number IS NOT DISTINCT FROM p_lot_number)
    FOR UPDATE;

    IF v_src_inventory_id IS NULL THEN
        RAISE EXCEPTION 'No inventory found for product % at source location % (lot: %)', p_product_id, p_from_location_id, p_lot_number;
    END IF;

    IF v_src_qoh < p_quantity THEN
        RAISE EXCEPTION 'Insufficient quantity at source: have %, need %', v_src_qoh, p_quantity;
    END IF;

    -- Lock or create destination inventory row
    SELECT inventory_id, quantity_on_hand INTO v_dest_inventory_id, v_dest_qoh
    FROM inventory
    WHERE product_id = p_product_id
      AND location_id = p_to_location_id
      AND (lot_number IS NOT DISTINCT FROM p_lot_number)
    FOR UPDATE;

    IF v_dest_inventory_id IS NULL THEN
        -- Insert new inventory record at destination
        INSERT INTO inventory (product_id, location_id, warehouse_id, quantity_on_hand, quantity_allocated, lot_number, last_movement_date)
        VALUES (p_product_id, p_to_location_id, v_dest_warehouse_id, p_quantity, 0, p_lot_number, CURRENT_TIMESTAMP)
        RETURNING inventory_id INTO v_dest_inventory_id;

        v_dest_qoh := p_quantity;
    ELSE
        -- Update destination quantity
        v_dest_qoh := v_dest_qoh + p_quantity;
        UPDATE inventory
        SET quantity_on_hand = v_dest_qoh, last_movement_date = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
        WHERE inventory_id = v_dest_inventory_id;
    END IF;

    -- Update source quantity
    v_src_qoh := v_src_qoh - p_quantity;
    UPDATE inventory
    SET quantity_on_hand = v_src_qoh, last_movement_date = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
    WHERE inventory_id = v_src_inventory_id;

    -- Create transaction records (audit trail)
    INSERT INTO inventory_transactions (product_id, location_id, warehouse_id, order_id, transaction_type, quantity_change, quantity_before, quantity_after, lot_number, reason, performed_by, transaction_date)
    VALUES (p_product_id, p_from_location_id, v_src_warehouse_id, NULL, 'transfer', -p_quantity, v_src_qoh + p_quantity, v_src_qoh, p_lot_number, p_reason, p_performed_by, CURRENT_TIMESTAMP);

    INSERT INTO inventory_transactions (product_id, location_id, warehouse_id, order_id, transaction_type, quantity_change, quantity_before, quantity_after, lot_number, reason, performed_by, transaction_date)
    VALUES (p_product_id, p_to_location_id, v_dest_warehouse_id, NULL, 'transfer', p_quantity, v_dest_qoh - p_quantity, v_dest_qoh, p_lot_number, p_reason, p_performed_by, CURRENT_TIMESTAMP);

    RETURN;
EXCEPTION
    WHEN others THEN
        RAISE;
END;
$$ LANGUAGE plpgsql;

-- End of move_inventory function
