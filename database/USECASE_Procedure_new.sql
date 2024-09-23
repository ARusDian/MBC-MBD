USE loket_mbc;

-- Trigger --
DELIMITER //

CREATE TRIGGER trg_enforce_unique_email
BEFORE INSERT ON users
FOR EACH ROW
BEGIN
    DECLARE email_count INT;
    SELECT COUNT(*) INTO email_count
    FROM users
    WHERE email = NEW.email;

    IF email_count > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Email already exists.';
    END IF;
END//

DELIMITER ;

DELIMITER //

CREATE TRIGGER trg_cleanup_expired_sessions
AFTER UPDATE ON sessions
FOR EACH ROW
BEGIN
    IF OLD.expire < NOW() THEN
        DELETE FROM sessions WHERE sid = OLD.sid;
    END IF;
END//

DELIMITER ;

DELIMITER //

CREATE TRIGGER trg_before_insert_transaction
BEFORE INSERT ON transactions
FOR EACH ROW
BEGIN
    -- Validasi: Periksa apakah ticket_id sudah ada di tabel transactions
    DECLARE v_ticket_exists INT;

    SELECT COUNT(*)
    INTO v_ticket_exists
    FROM transactions
    WHERE ticket_id = NEW.ticket_id;

    IF v_ticket_exists > 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Error! Ticket ID already exists in transactions table.';
    END IF;

    -- Validasi: Periksa apakah redeemed_amount tidak melebihi ticket_amount
    IF NEW.redeemed_amount > NEW.ticket_amount THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error! Redeemed amount exceeds ticket amount.';
    END IF;
END //

DELIMITER ;
DELIMITER //

CREATE TRIGGER trg_before_update_transaction
BEFORE UPDATE ON transactions
FOR EACH ROW
BEGIN
    -- Validasi: Periksa apakah ticket_id yang akan diupdate ada di tabel transactions
    DECLARE v_ticket_exists INT;

    SELECT COUNT(*)
    INTO v_ticket_exists
    FROM transactions
    WHERE ticket_id = OLD.ticket_id;

    IF v_ticket_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error! Ticket ID does not exist in transactions table.';
    END IF;

    -- Validasi: Periksa apakah redeemed_amount tidak melebihi ticket_amount
    IF NEW.redeemed_amount > NEW.ticket_amount THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error! Redeemed amount exceeds ticket amount.';
    END IF;
END //

DELIMITER ;

DELIMITER //

CREATE TRIGGER trg_after_insert_transaction
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    -- Update ticket stock
    UPDATE ticket_types
    SET stock = stock - NEW.ticket_amount
    WHERE id = NEW.ticket_type_id;
END //

DELIMITER ;

-- Function -- 

CREATE FUNCTION validate_email(p_email VARCHAR(255))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    -- Check if the email matches the pattern
    RETURN p_email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$';
END;

DELIMITER //

-- Buyer --
-- Melihat Event --
DELIMITER // 

CREATE PROCEDURE search_events(
    IN p_name VARCHAR(255),
    IN p_start_year INT,
    IN p_start_month INT,
    IN p_location VARCHAR(255)
) BEGIN -- If all parameters are NULL, return all data
IF p_name IS NULL
AND p_start_year IS NULL
AND p_start_month IS NULL
AND p_location IS NULL THEN
SELECT
    id,
    name,
    description,
    start_date,
    end_date
FROM
    events;

ELSE -- If any parameters are provided, use filters according to non-NULL parameters
SELECT
    id,
    name,
    description,
    start_date,
    end_date
FROM
    events
WHERE
    (
        p_name IS NULL
        OR name LIKE CONCAT('%', p_name, '%')
    )
    AND (
        p_start_year IS NULL
        OR YEAR(start_date) = p_start_year
    )
    AND (
        p_start_month IS NULL
        OR MONTH(start_date) = p_start_month
    )
    AND (
        p_location IS NULL
        OR location LIKE CONCAT('%', p_location, '%')
    );

END IF;

END // 

DELIMITER;

-- CALL search_events('Concert', 2024, 9, 'New York');
-- CALL search_events(NULL, NULL, NULL, 'New York');
-- 2. Membeli Tiket --
-- DROP PROCEDURE purchase_ticket;

DELIMITER //

CREATE PROCEDURE purchase_ticket(
    IN p_ticket_amount INT,
    IN p_base_price INT,
    IN p_user_id INT,
    IN p_ticket_type_id INT,
    IN p_payment_method VARCHAR(255),
    IN p_payment_status VARCHAR(255),
    IN p_external_id VARCHAR(255)
) 
BEGIN
    DECLARE v_current_ticket_amount INT;
    DECLARE v_total_price INT;
    DECLARE v_max_buy INT;
    DECLARE v_error_message TEXT;
    DECLARE v_platform_fee INT;

    -- Start Transaction
    START TRANSACTION;

    -- Error Handling: Check for NULL or Invalid Inputs
    IF p_user_id IS NULL 
    OR p_ticket_amount IS NULL
    OR p_base_price IS NULL
    OR p_ticket_type_id IS NULL
    OR p_payment_method IS NULL
    OR p_payment_status IS NULL
    OR p_external_id IS NULL THEN
        SET v_error_message = 'Input parameters cannot be NULL.';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_message;
    END IF;

    -- Check User Ticket Limit
    SELECT COALESCE(SUM(ticket_amount), 0) INTO v_current_ticket_amount
    FROM transactions
    WHERE user_id = p_user_id;

    SELECT max_buy INTO v_max_buy
    FROM ticket_types
    WHERE id = p_ticket_type_id;

    IF v_max_buy IS NULL THEN
        SET v_error_message = 'Ticket type does not exist.';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_message;
    END IF;

    IF (v_current_ticket_amount + p_ticket_amount) > v_max_buy THEN
        SET v_error_message = CONCAT(
            'Sisa Tiket yang dapat Anda beli hanya sebanyak ',
            v_max_buy - v_current_ticket_amount,
            ' tiket lagi!'
        );
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_message;
    END IF;

    -- Check Ticket Stock
    IF p_ticket_amount > (
        SELECT stock
        FROM ticket_types
        WHERE id = p_ticket_type_id
    ) THEN
        SET v_error_message = 'Tiket yang tersedia tidak cukup dengan jumlah yang ingin Anda beli';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_message;
    END IF;

    -- Get Platform Fee
    SELECT platform_fee INTO v_platform_fee
    FROM ticket_types
    WHERE id = p_ticket_type_id;

    -- Calculate Total Price
    SET v_total_price = (p_ticket_amount * p_base_price) + v_platform_fee;

    -- Create the Transaction Record
    INSERT INTO transactions (
        ticket_amount,
        base_price,
        total_price,
        redeemed_amount,
        buy_date,
        pay_date,
        payment_method,
        payment_status,
        ticket_id,
        ticket_status,
        ticket_barcode,
        external_id,
        ticket_type_id,
        user_id
    )
    VALUES (
        p_ticket_amount,
        p_base_price,
        v_total_price,
        0,
        NOW(),
        NULL, -- pay_date, set it later if needed
        p_payment_method,
        p_payment_status,
        "-",
        "-",
        "-",
        p_external_id,
        p_ticket_type_id,
        p_user_id
    );

    -- Error Handling: Check if Stock Update Was Successful
    IF ROW_COUNT() = 0 THEN
        SET v_error_message = 'Failed to update ticket stock. Ticket type might not exist.';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_message;
    END IF;

    -- Commit the Transaction
    COMMIT;
END //

DELIMITER ;


-- CALL purchase_ticket(
--     50,
--     1,
--     1,
--     1,
--     'Credit Card',
--     'Paid',
--     '2123',
--     '123',
--     'Booked',
--     'barcode_url',
--     0
-- );

-- Pihak Ketiga --
-- Konfirmasi Pembayaran Berhasil
DELIMITER //

CREATE PROCEDURE sp_update_payment_status(
    IN p_status VARCHAR(255),
    IN p_external_id VARCHAR(255),
    IN p_barcode_url VARCHAR(255),
    IN p_ticket_id VARCHAR(255)
)
BEGIN
    DECLARE now TIMESTAMP;
    DECLARE data_trans_id INT;
    DECLARE data_ticket_type_id INT;
    DECLARE data_ticket_amount INT;
    DECLARE data_total_price INT;
    DECLARE data_payment_method VARCHAR(255);
    DECLARE ticket_type_name VARCHAR(255);

    SET now = CURRENT_TIMESTAMP;
    SET data_trans_id = (SELECT id FROM transactions WHERE external_id = p_external_id LIMIT 1);

    IF p_status = 'PAID' THEN
        -- Retrieve necessary transaction and ticket type data
        SELECT ticket_amount, total_price, payment_method, ticket_type_id
        INTO data_ticket_amount, data_total_price, data_payment_method, data_ticket_type_id
        FROM transactions
        WHERE id = data_trans_id;

        SET ticket_type_name = (SELECT name FROM ticket_types WHERE id = data_ticket_type_id);

        -- Assume barcode generation and file storage is handled externally

        -- Update the transaction with payment status and ticket details
        UPDATE transactions
        SET payment_status = p_status,
            ticket_id = p_ticket_id,
            ticket_status = 'active',
            ticket_barcode = p_barcode_url,
            pay_date = now
        WHERE external_id = p_external_id;

        -- Send success email (assumed to be handled by an external application)

    ELSEIF p_status = 'EXPIRED' THEN
        -- Update transaction with EXPIRED status and clear ticket details
        UPDATE transactions
        SET payment_status = p_status
        WHERE external_id = p_external_id;

        -- Restore ticket stock
        SET data_ticket_amount = (SELECT ticket_amount FROM transactions WHERE external_id = p_external_id);
        SET data_ticket_type_id = (SELECT ticket_type_id FROM transactions WHERE external_id = p_external_id);

        UPDATE ticket_types
        SET stock = stock + data_ticket_amount
        WHERE id = data_ticket_type_id;

    END IF;
END//

DELIMITER ;

-- CALL sp_update_payment_status('PAID', '34aac638-836e-4b22-9ebc-c6e6d20db42a','https://example.com/barcode/34aac638-836e-4b22-9ebc-c6e6d20db42a.png');

-- Admin -- 
-- Manajamen Event --
-- 1. Melihat Daftar Event --
DELIMITER // 

CREATE PROCEDURE sp_list_events() BEGIN
SELECT
    name AS "Nama Event",
    start_date AS "Tanggal Mulai",
    end_date AS "Tanggal Selesai",
    location AS "Lokasi"
FROM
    events;

END // DELIMITER;

-- 2. Melihat Detail Event --
DELIMITER // 
CREATE PROCEDURE sp_event_detail(IN p_id INT) BEGIN -- Event Details
SELECT
    e.name AS "Nama Event",
    e.description AS "Deskripsi",
    e.start_date AS "Tanggal Mulai",
    e.end_date AS "Tanggal Selesai",
    e.location AS "Lokasi"
FROM
    events e
WHERE
    e.id = p_id;

-- Transactions for the Event
SELECT
    t.id AS "ID Transaksi",
    t.ticket_type_id AS "ID Tipe Tiket",
    tt.name AS "Nama Tipe Tiket",
    t.ticket_amount AS "Jumlah Tiket",
    t.total_price AS "Total Harga",
    t.base_price AS "Harga Dasar",
    t.payment_method AS "Metode Pembayaran",
    t.payment_status AS "Status Pembayaran",
    u.name AS "Nama Pengguna"
FROM
    transactions t
    JOIN ticket_types tt ON t.ticket_type_id = tt.id
    JOIN users u ON t.user_id = u.id
WHERE
    tt.event_id = p_id;

END //

DELIMITER ;

-- CALL sp_event_detail(1);

-- 3. Tambah Event --
DELIMITER //

CREATE PROCEDURE sp_add_event(
    IN p_name VARCHAR(255),
    IN p_description TEXT,
    IN p_start_date DATE,
    IN p_end_date DATE,
    IN p_location VARCHAR(255),
    IN p_user_id INT
)
BEGIN
    -- Declare variables
    DECLARE v_event_id INT;

    -- Start transaction
    START TRANSACTION;

    -- Insert the event
    INSERT INTO events (
        name,
        description,
        start_date,
        end_date,
        location
    )
    VALUES (
        p_name,
        p_description,
        p_start_date,
        p_end_date,
        p_location
    );
    
    -- Get the ID of the newly inserted event
    SET v_event_id = LAST_INSERT_ID();
    
    -- Insert user activity log
    INSERT INTO user_activities (user_id, activity)
    VALUES (p_user_id, CONCAT('Create Event ', p_name, ' with id ', v_event_id));
    
    -- Commit transaction
    COMMIT;
END //

DELIMITER ;




-- 4. Update Event --
DELIMITER //

CREATE PROCEDURE sp_update_event(
    IN p_id INT,
    IN p_name VARCHAR(255),
    IN p_description TEXT,
    IN p_start_date DATE,
    IN p_end_date DATE,
    IN p_location VARCHAR(255),
    IN p_user_id INT
)
BEGIN
    -- Start transaction
    START TRANSACTION;
    
    -- Update the event
    UPDATE events
    SET 
        name = p_name, 
        description = p_description, 
        start_date = p_start_date,
        end_date = p_end_date, 
        location = p_location
    WHERE 
        id = p_id;
    
    -- Check if the update was successful
    IF ROW_COUNT() > 0 THEN
        -- Insert user activity log
        INSERT INTO user_activities (user_id, activity)
        VALUES (p_user_id, CONCAT('Update Event ', p_name, ' with id ', p_id));
        
        -- Commit transaction
        COMMIT;
    ELSE
        -- Rollback transaction if update fails
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Update failed or event not found';
    END IF;
END //

DELIMITER ;



-- 5. Hapus Event --
DELIMITER //

CREATE PROCEDURE sp_delete_event(
    IN p_id INT,
    IN p_user_id INT
)
BEGIN
    -- Declare the variable at the beginning
    DECLARE v_event_name VARCHAR(255);
    
    -- Start transaction
    START TRANSACTION;
    
    -- Get the name of the event to log it
    SELECT name INTO v_event_name
    FROM events
    WHERE id = p_id;
    
    -- Check if the event exists
    IF v_event_name IS NOT NULL THEN
        -- Delete the event
        DELETE FROM events
        WHERE id = p_id;
        
        -- Insert user activity log
        INSERT INTO user_activities (user_id, activity)
        VALUES (p_user_id, CONCAT('Delete Event ', v_event_name, ' with id ', p_id));
        
        -- Commit transaction
        COMMIT;
    ELSE
        -- Rollback transaction if event not found
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Event not found';
    END IF;
END //

DELIMITER ;

CALL sp_list_events();

-- Tambah Event
-- CALL sp_add_event(
--     'Music Concert',          -- p_name
--     'An amazing music concert', -- p_description
--     '2024-09-03 04:20:09',    -- p_start_date
--     '2024-09-03 04:20:09',    -- p_end_date
--     'New York',               -- p_city
--     1
-- );


-- Update Event
-- CALL sp_update_event(
--     1, 
--     'Updated Music Concert', 
--     'An updated description for the music concert', 
--     '2024-09-11', 
--     '2024-09-13', 
--     'Los Angeles', 
--     'new-image.jpg', 
--     1
-- );


-- Hapus Event
-- CALL sp_delete_event(
--     1, -- Assuming the event id is 1
--     1  -- Assuming user_id is 1
-- );


-- Manajemen Jenis Tiket --
-- 1. Melihat Daftar Jenis Tiket --
DELIMITER //

CREATE PROCEDURE sp_list_ticket_types() 
BEGIN
    SELECT
        name AS "Nama Tipe Tiket",
        price AS "Harga",
        stock AS "Stok",
        max_buy AS "Maksimal Pembelian",
        platform_fee AS "Biaya Platform",
        event_id AS "ID Event"
    FROM
        ticket_types;
END //

DELIMITER ;

-- 2. Melihat Detail Jenis Tiket --
DELIMITER //

CREATE PROCEDURE sp_ticket_type_detail(IN p_id INT) 
BEGIN
    -- Ticket Type Details
    SELECT
        tt.name AS "Nama Tipe Tiket",
        tt.price AS "Harga",
        tt.stock AS "Stok",
        tt.max_buy AS "Maksimal Pembelian",
        tt.platform_fee AS "Biaya Platform",
        tt.event_id AS "ID Event"
    FROM
        ticket_types tt
    WHERE
        tt.id = p_id;

    -- Transactions for the Ticket Type
    SELECT
        t.id AS "ID Transaksi",
        t.ticket_type_id AS "ID Tipe Tiket",
        tt.name AS "Nama Tipe Tiket",
        t.ticket_amount AS "Jumlah Tiket",
        t.total_price AS "Total Harga",
        t.base_price AS "Harga Dasar",
        t.payment_method AS "Metode Pembayaran",
        t.payment_status AS "Status Pembayaran",
        u.name AS "Nama Pengguna"
    FROM
        transactions t
        JOIN ticket_types tt ON t.ticket_type_id = tt.id
        JOIN users u ON t.user_id = u.id
    WHERE
        tt.id = p_id;
END //

DELIMITER ;

-- 3. Tambah Jenis Tiket --
DELIMITER //

-- CREATE PROCEDURE sp_add_ticket_type(
--     IN p_name VARCHAR(255),
--     IN p_price INT,
--     IN p_stock INT,
--     IN p_max_buy INT,
--     IN p_platform_fee INT,
--     IN p_event_id INT,
--     IN p_user_id INT
-- )
BEGIN
    -- Declare variables
    DECLARE v_ticket_type_id INT;

    -- Start transaction
    START TRANSACTION;

    -- Insert the ticket type
    INSERT INTO ticket_types (
        name,
        price,
        stock,
        max_buy,
        platform_fee,
        event_id
    )
    VALUES (
        p_name,
        p_price,
        p_stock,
        p_max_buy,
        p_platform_fee,
        p_event_id
    );
    
    -- Get the ID of the newly inserted ticket type
    SET v_ticket_type_id = LAST_INSERT_ID();
    
    -- Insert user activity log
    INSERT INTO user_activities (user_id, activity)
    VALUES (p_user_id, CONCAT('Add Ticket Type ', p_name, ' with id ', v_ticket_type_id));
    
    -- Commit transaction
    COMMIT;
END //

DELIMITER ;

-- 4. Update Jenis Tiket --
DELIMITER //

CREATE PROCEDURE sp_update_ticket_type(
    IN p_id INT,
    IN p_name VARCHAR(255),
    IN p_price INT,
    IN p_stock INT,
    IN p_max_buy INT,
    IN p_platform_fee INT,
    IN p_user_id INT
)
BEGIN
    -- Start transaction
    START TRANSACTION;
    
    -- Update the ticket type
    UPDATE ticket_types
    SET 
        name = p_name, 
        price = p_price, 
        stock = p_stock,
        max_buy = p_max_buy, 
        platform_fee = p_platform_fee
    WHERE 
        id = p_id;
    
    -- Check if the update was successful
    IF ROW_COUNT() > 0 THEN
        -- Insert user activity log
        INSERT INTO user_activities (user_id, activity)
        VALUES (p_user_id, CONCAT('Update Ticket Type ', p_name, ' with id ', p_id));
        
        -- Commit transaction
        COMMIT;
    ELSE
        -- Rollback transaction if update fails
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Update failed or ticket type not found';
    END IF;
END //

DELIMITER ;

-- 5. Hapus Jenis Tiket --
DELIMITER //

CREATE PROCEDURE sp_delete_ticket_type(
    IN p_id INT,
    IN p_user_id INT
)
BEGIN
    -- Declare the variable at the beginning
    DECLARE v_ticket_type_name VARCHAR(255);
    
    -- Start transaction
    START TRANSACTION;
    
    -- Get the name of the ticket type to log it
    SELECT name INTO v_ticket_type_name
    FROM ticket_types
    WHERE id = p_id;
    
    -- Check if the ticket type exists
    IF v_ticket_type_name IS NOT NULL THEN
        -- Delete the ticket type
        DELETE FROM ticket_types
        WHERE id = p_id;
        
        -- Insert user activity log
        INSERT INTO user_activities (user_id, activity)
        VALUES (p_user_id, CONCAT('Delete Ticket Type ', v_ticket_type_name, ' with id ', p_id));
        
        -- Commit transaction
        COMMIT;
    ELSE
        -- Rollback transaction if ticket type not found
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Ticket Type not found';
    END IF;
END //

DELIMITER ;
-- CALL --

-- List Ticket Types
-- CALL sp_list_ticket_types();

-- Add Ticket Type
-- CALL sp_add_ticket_type(
--     'VIP Pass',           -- p_name
--     150,                  -- p_price
--     100,                  -- p_stock
--     5,                    -- p_max_buy
--     20,                   -- p_platform_fee
--     3,                    -- p_event_id
--     1                     -- p_user_id
-- );

-- Update Ticket Type
-- CALL sp_update_ticket_type(
--     4,                    -- p_id
--     'Updated VIP Pass',   -- p_name
--     200,                  -- p_price
--     80,                   -- p_stock
--     10,                   -- p_max_buy
--     25,                   -- p_platform_fee
--     1                     -- p_user_id
-- );

-- Delete Ticket Type
-- CALL sp_delete_ticket_type(
--     4,                    -- p_id
--     1                     -- p_user_id
-- );

-- Daftar Transaksi Keseluruhan
DELIMITER //

CREATE PROCEDURE search_transactions(
    IN p_ticket_id VARCHAR(255),
    IN p_user_name VARCHAR(255),
    IN p_ticket_type_name VARCHAR(255),
    IN p_event_name VARCHAR(255),
    IN p_payment_method VARCHAR(255),
    IN p_payment_status VARCHAR(255),
    IN p_buy_start_date DATE,
    IN p_buy_end_date DATE,
    IN p_pay_start_date DATE,
    IN p_pay_end_date DATE
)
BEGIN
    -- If all parameters are NULL, return all data
    IF p_ticket_id IS NULL
    AND p_user_name IS NULL
    AND p_ticket_type_name IS NULL
    AND p_event_name IS NULL
    AND p_payment_method IS NULL
    AND p_payment_status IS NULL
    AND p_buy_start_date IS NULL
    AND p_buy_end_date IS NULL
    AND p_pay_start_date IS NULL
    AND p_pay_end_date IS NULL THEN

        SELECT
            t.id AS "Tiket Id",
            u.name AS "Nama Pembeli",
            tt.name AS "Jenis Tiket",
            e.name AS "Event",
            t.payment_method AS "Metode Pembayaran",
            t.payment_status AS "Status Pembayaran",
            DATE_FORMAT(t.buy_date, '%d-%m-%Y %H:%i:%s') AS "Waktu Pembelian",
            DATE_FORMAT(t.pay_date, '%d-%m-%Y %H:%i:%s') AS "Waktu Pembayaran"
        FROM
            transactions t
            JOIN ticket_types tt ON t.ticket_type_id = tt.id
            JOIN events e ON tt.event_id = e.id
            JOIN users u ON t.user_id = u.id;

    ELSE -- If any parameters are provided, use filters according to non-NULL parameters

        SELECT
            t.id AS "Tiket Id",
            u.name AS "Nama Pembeli",
            tt.name AS "Jenis Tiket",
            e.name AS "Event",
            t.payment_method AS "Metode Pembayaran",
            t.payment_status AS "Status Pembayaran",
            DATE_FORMAT(t.buy_date, '%d-%m-%Y %H:%i:%s') AS "Waktu Pembelian",
            DATE_FORMAT(t.pay_date, '%d-%m-%Y %H:%i:%s') AS "Waktu Pembayaran"
        FROM
            transactions t
            JOIN ticket_types tt ON t.ticket_type_id = tt.id
            JOIN events e ON tt.event_id = e.id
            JOIN users u ON t.user_id = u.id
        WHERE
            (p_ticket_id IS NULL OR t.ticket_id = p_ticket_id)
            AND (p_user_name IS NULL OR u.name LIKE CONCAT('%', p_user_name, '%'))
            AND (p_ticket_type_name IS NULL OR tt.name LIKE CONCAT('%', p_ticket_type_name, '%'))
            AND (p_event_name IS NULL OR e.name LIKE CONCAT('%', p_event_name, '%'))
            AND (p_payment_method IS NULL OR t.payment_method LIKE CONCAT('%', p_payment_method, '%'))
            AND (p_payment_status IS NULL OR t.payment_status LIKE CONCAT('%', p_payment_status, '%'))
            AND (p_buy_start_date IS NULL OR t.buy_date >= p_buy_start_date)
            AND (p_buy_end_date IS NULL OR t.buy_date <= p_buy_end_date)
            AND (p_pay_start_date IS NULL OR t.pay_date >= p_pay_start_date)
            AND (p_pay_end_date IS NULL OR t.pay_date <= p_pay_end_date);

    END IF;

END //

DELIMITER ;


-- CALL search_transactions(
--     NULL,               -- p_ticket_id
--     'Doe',         -- p_user_name
--     'VIP',             -- p_ticket_type_name
--     'Concert',         -- p_event_name
--     'Credit Card',     -- p_payment_method
--     'Paid',            -- p_payment_status
--     '2024-01-01',      -- p_buy_start_date
--     '2024-12-31',      -- p_buy_end_date
--     '2024-01-01',      -- p_pay_start_date
--     '2024-12-31'       -- p_pay_end_date
-- );

-- CALL search_transactions(
--     NULL,  -- p_ticket_id
--     NULL,  -- p_user_name
--     NULL,  -- p_ticket_type_name
--     NULL,  -- p_event_name
--     NULL,  -- p_payment_method
--     NULL,  -- p_payment_status
--     NULL,  -- p_buy_start_date
--     NULL,  -- p_buy_end_date
--     NULL,  -- p_pay_start_date
--     NULL   -- p_pay_end_date
-- );




-- Redeem Ticket --
DELIMITER ;;

CREATE PROCEDURE `sp_redeem_ticket`(
    IN p_ticket_id VARCHAR(255),
    IN p_redeemed_amount INT,
    IN p_latitude DECIMAL(10, 6),
    IN p_longitude DECIMAL(10, 6),
    IN p_user_id INT
)
BEGIN
    DECLARE v_ticket_amount INT;
    DECLARE v_current_redeemed_amount INT;
    DECLARE v_ticket_status VARCHAR(255);
    DECLARE v_transaction_id INT;

    -- Start transaction
    START TRANSACTION;

    -- Check if the ticket exists and get its details
    SELECT id, ticket_amount, redeemed_amount, ticket_status
    INTO v_transaction_id, v_ticket_amount, v_current_redeemed_amount, v_ticket_status
    FROM transactions
    WHERE ticket_id = p_ticket_id
    FOR UPDATE;

    IF v_transaction_id IS NULL THEN
        -- Ticket not found
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ticket ID Not Found!';
    ELSE
        -- Check redemption status and handle accordingly
        IF (v_current_redeemed_amount + p_redeemed_amount) > v_ticket_amount THEN
            -- Redemption exceeds total tickets
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error! Redeem request was out of total purchased tickets';
        ELSE
            IF v_current_redeemed_amount = 0 THEN
                -- First-time redemption
                UPDATE transactions
                SET ticket_status = CONCAT('Redeemed for ', p_redeemed_amount, ' tickets'),
                    redeemed_amount = p_redeemed_amount
                WHERE id = v_transaction_id;
            ELSEIF (v_current_redeemed_amount + p_redeemed_amount) = v_ticket_amount THEN
                -- Redeem all tickets
                UPDATE transactions
                SET ticket_status = 'Redeemed for all tickets',
                    redeemed_amount = v_ticket_amount
                WHERE id = v_transaction_id;
            ELSE
                -- Partial redemption
                UPDATE transactions
                SET ticket_status = CONCAT('Redeemed for ', v_current_redeemed_amount + p_redeemed_amount, ' tickets'),
                    redeemed_amount = v_current_redeemed_amount + p_redeemed_amount
                WHERE id = v_transaction_id;
            END IF;

            -- Insert record into RedeemHistory
            INSERT INTO redeem_histories (
                user_id, transaction_id, amount, latitude, longitude
            )
            VALUES (
                p_user_id,
                v_transaction_id,
                p_redeemed_amount,
                p_latitude,
                p_longitude
            );

            -- Commit transaction
            COMMIT;
        END IF;
    END IF;
END ;;

DELIMITER ;



-- Menguji prosedur dengan parameter yang valid
-- CALL sp_redeem_ticket(1, 5, 37.7749, -122.4194, 1);

-- Menguji dengan nilai redemption yang lebih dari tiket yang tersedia
-- CALL sp_redeem_ticket(5, 15, 37.7749, -122.4194, 1);

-- Menguji dengan ID tiket yang tidak ada
-- CALL sp_redeem_ticket(999, 5, 37.7749, -122.4194,1 );

-- Superadmin --
-- Manajemen User --
-- 1. Melihat Daftar User --
DELIMITER //
CREATE PROCEDURE sp_list_users() 
BEGIN
    SELECT
        name AS 'Nama User',
        email AS 'Email',
        role AS 'Status'
    FROM
        users;
END //

-- Kembalikan delimiter ke default
DELIMITER ;


-- 2. Melihat Detail User --
DELIMITER //

CREATE PROCEDURE sp_user_detail(IN p_id INT) 
BEGIN
    -- User Details
    SELECT
        u.name AS "Nama User",
        u.email AS "Email",
        u.role AS "Status"
    FROM
        users u
    WHERE
        u.id = p_id;

    -- Transactions for the User
    SELECT
        t.id AS "ID Transaksi",
        t.ticket_type_id AS "ID Tipe Tiket",
        tt.name AS "Nama Tipe Tiket",
        t.ticket_amount AS "Jumlah Tiket",
        t.total_price AS "Total Harga",
        t.base_price AS "Harga Dasar",
        t.payment_method AS "Metode Pembayaran",
        t.payment_status AS "Status Pembayaran",
        e.name AS "Nama Event"
    FROM
        transactions t
        JOIN ticket_types tt ON t.ticket_type_id = tt.id
        JOIN events e ON tt.event_id = e.id
    WHERE
        t.user_id = p_id;
END //

DELIMITER ;

DELIMITER //

CREATE PROCEDURE sp_user_detail_by_email(IN p_email VARCHAR(255))
BEGIN
    -- User Details
    SELECT
        id,
        u.name AS "Nama User",
        u.email AS "Email",
        u.role AS "Status",
        password
    FROM
        users u
    WHERE
        u.email = p_email;
    END //

DELIMITER ;

-- 3. Tambah User --
DELIMITER //

CREATE PROCEDURE sp_add_user(
    IN p_name VARCHAR(255),
    IN p_email VARCHAR(255),
    IN p_password VARCHAR(255),
    IN p_role VARCHAR(10),
    IN p_creator_id INT
)
BEGIN
    -- Declare variables
    DECLARE v_user_id INT;

    -- Start transaction
    START TRANSACTION;

    -- Validate email
    IF NOT validate_email(p_email) THEN
        -- Rollback transaction if email is invalid
        ROLLBACK;
        -- Signal an error
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid email format';
        -- No need to use LEAVE, procedure stops here
    ELSE
        -- Insert the user
        INSERT INTO users (
            name,
            email,
            password,
            role
        )
        VALUES (
            p_name,
            p_email,
            p_password,
            p_role
        );
        
        -- Get the ID of the newly inserted user
        SET v_user_id = LAST_INSERT_ID();
        
        -- Insert user activity log
        INSERT INTO user_activities (user_id, activity)
        VALUES (p_creator_id, CONCAT('Add User ', p_name, ' with id ', v_user_id));
        
        -- Commit transaction
        COMMIT;
    END IF;
END //

DELIMITER ;


-- 4. Update User --
DELIMITER //

CREATE PROCEDURE sp_update_user(
    IN p_id INT,
    IN p_name VARCHAR(255),
    IN p_email VARCHAR(255),
    IN p_password VARCHAR(255),
    IN p_role VARCHAR(10),
    IN p_user_id INT
)
BEGIN
    -- Start transaction
    START TRANSACTION;

    -- Validate email
    IF NOT validate_email(p_email) THEN
        -- Rollback transaction if email is invalid
        ROLLBACK;
        -- Signal an error
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid email format';
        -- No need for LEAVE, execution will stop here
    ELSE
        -- Update the user
        UPDATE users
        SET 
            name = p_name, 
            email = p_email, 
            password = p_password,
            role = p_role
        WHERE 
            id = p_id;
        
        -- Check if the update was successful
        IF ROW_COUNT() > 0 THEN
            -- Insert user activity log
            INSERT INTO user_activities (user_id, activity)
            VALUES (p_user_id, CONCAT('Update User ', p_name, ' with id ', p_id));
            
            -- Commit transaction
            COMMIT;
        ELSE
            -- Rollback transaction if update fails
            ROLLBACK;
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Update failed or user not found';
        END IF;
    END IF;
END //

DELIMITER ;



-- 5. Hapus User --
DELIMITER //

CREATE PROCEDURE sp_delete_user(
    IN p_id INT,
    IN p_user_id INT
)
BEGIN
    -- Declare the variable at the beginning
    DECLARE v_user_name VARCHAR(255);
    
    -- Start transaction
    START TRANSACTION;
    
    -- Get the name of the user to log it
    SELECT name INTO v_user_name
    FROM users
    WHERE id = p_id;
    
    -- Check if the user exists
    IF v_user_name IS NOT NULL THEN
        -- Delete the user
        DELETE FROM users
        WHERE id = p_id;
        
        -- Insert user activity log
        INSERT INTO user_activities (user_id, activity)
        VALUES (p_user_id, CONCAT('Delete User ', v_user_name, ' with id ', p_id));
        
        -- Commit transaction
        COMMIT;
    ELSE
        -- Rollback transaction if user not found
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'User not found';
    END IF;
END //

DELIMITER ;


-- List Users
-- CALL sp_list_users();

-- Add User
-- CALL sp_add_user(
--     'John Doe',           -- p_name
--     'john.doe@example.com', -- p_email
--     'password123',       -- p_password
--     1,                   -- p_role_id
--     1                    -- p_user_id
-- );

-- Update User
-- CALL sp_update_user(
--     1,                    -- p_id
--     'Jane Doe',           -- p_name
--     'jane.doe@example.com', -- p_email
--     'newpassword123',    -- p_password
--     1,                    -- p_role_id
--     1                     -- p_user_id
-- );

-- Delete User
-- CALL sp_delete_user(
--     3,                    -- p_id
--     1                     -- p_user_id
-- );

-- Melihat Riwayat Aktivitas --

CREATE VIEW vw_user_activities AS
SELECT
    user_activities.id AS activity_id,
    user_activities.activity,
    user_activities.createdAt,
    users.name AS user_name
FROM
    user_activities
    LEFT JOIN users ON user_activities.user_id = users.id;

-- SELECT * FROM vw_user_activities;


-- Authorization --
-- Register -- 
DELIMITER //

CREATE PROCEDURE sp_register_user(
    IN p_name VARCHAR(255),
    IN p_email VARCHAR(255),
    IN p_password VARCHAR(255)
)
BEGIN
    DECLARE email_count INT;

    -- Check if the email already exists
    SELECT COUNT(*) INTO email_count
    FROM users
    WHERE email = p_email;

    IF email_count > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Email already exists.';
    ELSE
        -- Insert new user
        INSERT INTO users (name, email, password, role)
        VALUES (p_name, p_email, p_password, 'user');
    END IF;
END //

DELIMITER ;

DELIMITER //

CREATE PROCEDURE sp_user_login(
    IN p_user_id INT,
    IN p_role VARCHAR(10),
    IN p_session_id VARCHAR(255)
)
BEGIN
    -- Validate the role
    IF p_role NOT IN ('admin', 'superadmin', 'user') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid role specified';
    END IF;
    
    -- Insert the session details into the sessions table
    INSERT INTO sessions (sid, sess, expire)
    VALUES (p_session_id, CONCAT('user_', p_user_id, '_role_', p_role), DATE_ADD(NOW(), INTERVAL 1 HOUR));
END //

DELIMITER ;



-- LogOut -- 
DELIMITER //

CREATE PROCEDURE sp_user_logout(
    IN p_session_id VARCHAR(255)
)
BEGIN
    -- Delete the session
    DELETE FROM sessions WHERE sid = p_session_id;
END //

DELIMITER ;


-- CheckSession --
DELIMITER //

CREATE PROCEDURE sp_check_session(
    IN p_session_id VARCHAR(255),
    OUT p_valid_session BOOLEAN,
    OUT v_session VARCHAR(255)
)
BEGIN
    DECLARE session_expiry TIMESTAMP(6);
    -- Check if session exists and is not expired
    SELECT sess, expire INTO v_session, session_expiry
    FROM sessions
    WHERE sid = p_session_id;

    IF session_expiry IS NULL OR session_expiry < NOW() THEN
        SET p_valid_session = FALSE;
    ELSE
        SET p_valid_session = TRUE;
    END IF;
END //

DELIMITER ;







