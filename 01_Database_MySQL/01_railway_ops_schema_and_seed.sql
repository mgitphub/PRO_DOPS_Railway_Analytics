-- =============================================================================
-- DATABASE SETUP & DDL: PRO-DOPS
-- Location: Dalli Rajhara, Chhattisgarh, India
-- =============================================================================
DROP DATABASE IF EXISTS railway_ops_dallirajhara;
CREATE DATABASE railway_ops_dallirajhara CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE railway_ops_dallirajhara;

-- 1. Dim_Stations: Railway Station Master
CREATE TABLE Dim_Stations (
    station_code VARCHAR(10) PRIMARY KEY,
    station_name VARCHAR(100) NOT NULL,
    division VARCHAR(50) NOT NULL,
    zone VARCHAR(10) NOT NULL,
    state VARCHAR(50) NOT NULL
) ENGINE=InnoDB;

-- 2. Dim_IRCTC_Accounts: Agent vs Customer Account Roster
CREATE TABLE Dim_IRCTC_Accounts (
    account_id INT AUTO_INCREMENT PRIMARY KEY,
    irctc_username VARCHAR(50) UNIQUE NOT NULL,
    account_type ENUM('AGENT', 'CUSTOMER') NOT NULL,
    owner_name VARCHAR(100) NOT NULL,
    owner_phone VARCHAR(15) NOT NULL,
    commission_rate_pct DECIMAL(5,2) DEFAULT 0.00,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- 3. Dim_Trains: Static Train Master
CREATE TABLE Dim_Trains (
    train_number VARCHAR(10) PRIMARY KEY,
    train_name VARCHAR(100) NOT NULL,
    source_station VARCHAR(10) NOT NULL,
    dest_station VARCHAR(10) NOT NULL,
    route_via_dallirajhara BOOLEAN DEFAULT FALSE,
    FOREIGN KEY (source_station) REFERENCES Dim_Stations(station_code),
    FOREIGN KEY (dest_station) REFERENCES Dim_Stations(station_code)
) ENGINE=InnoDB;

-- 4. Dim_Customers: End Clients Seeking Bookings
CREATE TABLE Dim_Customers (
    customer_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    mobile_number VARCHAR(15) UNIQUE NOT NULL,
    city VARCHAR(50) DEFAULT 'Dalli Rajhara',
    state VARCHAR(50) DEFAULT 'Chhattisgarh',
    kyc_status ENUM('PENDING', 'VERIFIED') DEFAULT 'VERIFIED',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- 5. Fact_Ticket_Bookings: Core Operational Transactions
CREATE TABLE Fact_Ticket_Bookings (
    booking_id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT NOT NULL,
    pnr_number VARCHAR(10) UNIQUE,
    train_number VARCHAR(10) NOT NULL,
    travel_date DATE NOT NULL,
    travel_class ENUM('1A', '2A', '3A', 'SL', '2S', 'CC', 'EC') NOT NULL,
    quota_type ENUM('GENERAL', 'TATKAL', 'PREMIUM_TATKAL', 'LADIES', 'DEFENCE') NOT NULL,
    booking_timestamp DATETIME NOT NULL,
    booking_slot_hour TINYINT NOT NULL,
    account_id INT NOT NULL,
    advance_paid DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    irctc_base_fare DECIMAL(10,2) NOT NULL,
    service_charge_pct DECIMAL(5,2) NOT NULL,
    service_charge_amt DECIMAL(10,2) NOT NULL,
    gst_collected DECIMAL(10,2) NOT NULL,
    customer_id_payout DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    refund_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    net_operating_profit DECIMAL(10,2) NOT NULL,
    booking_status ENUM('CNF', 'RAC', 'WL', 'FAILED', 'REFUNDED') NOT NULL,
    wl_category ENUM('GNWL', 'RLWL', 'PQWL', 'TQWL', 'NONE') DEFAULT 'NONE',
    initial_wl_number INT DEFAULT 0,
    current_status VARCHAR(20) DEFAULT 'CNF',
    FOREIGN KEY (customer_id) REFERENCES Dim_Customers(customer_id),
    FOREIGN KEY (train_number) REFERENCES Dim_Trains(train_number),
    FOREIGN KEY (account_id) REFERENCES Dim_IRCTC_Accounts(account_id)
) ENGINE=InnoDB;

-- 6. Fact_Train_Telemetry: Live Operational Telemetry & Scraping Store
CREATE TABLE Fact_Train_Telemetry (
    telemetry_id INT AUTO_INCREMENT PRIMARY KEY,
    train_number VARCHAR(10) NOT NULL,
    observation_date DATE NOT NULL,
    source_platform ENUM('NTES', 'WHERE_IS_MY_TRAIN', 'INDIAN_RAIL_INFO', 'ETRAIN_INFO', 'IRCTC_CHARTS') NOT NULL,
    delay_departure_mins INT DEFAULT 0,
    delay_arrival_mins INT DEFAULT 0,
    chart_status ENUM('NOT_PREPARED', 'FIRST_CHART', 'SECOND_CHART') NOT NULL,
    chart_preparation_time DATETIME,
    available_vacant_berths INT DEFAULT 0,
    scraped_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (train_number) REFERENCES Dim_Trains(train_number)
) ENGINE=InnoDB;

-- INDEXES
CREATE INDEX idx_booking_ts ON Fact_Ticket_Bookings(booking_timestamp);
CREATE INDEX idx_pnr ON Fact_Ticket_Bookings(pnr_number);
CREATE INDEX idx_slot ON Fact_Ticket_Bookings(booking_slot_hour);
CREATE INDEX idx_telemetry_train ON Fact_Train_Telemetry(train_number, observation_date);

-- TRIGGERS
DELIMITER //

CREATE TRIGGER trg_calculate_booking_financials
BEFORE INSERT ON Fact_Ticket_Bookings
FOR EACH ROW
BEGIN
    DECLARE v_charge_pct DECIMAL(5,2);
    DECLARE v_id_type VARCHAR(10);
    DECLARE v_owner_payout_pct DECIMAL(5,2);

    SELECT account_type, commission_rate_pct 
    INTO v_id_type, v_owner_payout_pct
    FROM Dim_IRCTC_Accounts 
    WHERE account_id = NEW.account_id;

    IF NEW.booking_slot_hour IN (8, 10, 11) THEN
        SET v_charge_pct = 20.00;
    ELSE
        SET v_charge_pct = 10.00;
    END IF;

    SET NEW.service_charge_pct = v_charge_pct;
    SET NEW.service_charge_amt = ROUND((NEW.irctc_base_fare * (v_charge_pct / 100.00)), 2);
    SET NEW.gst_collected = ROUND((NEW.service_charge_amt * 0.18), 2);

    IF v_id_type = 'CUSTOMER' THEN
        SET NEW.customer_id_payout = ROUND((NEW.service_charge_amt * (v_owner_payout_pct / 100.00)), 2);
    ELSE
        SET NEW.customer_id_payout = 0.00;
    END IF;

    IF NEW.quota_type = 'PREMIUM_TATKAL' THEN
        IF NEW.advance_paid > (NEW.irctc_base_fare + NEW.service_charge_amt + NEW.gst_collected) THEN
            SET NEW.refund_amount = NEW.advance_paid - (NEW.irctc_base_fare + NEW.service_charge_amt + NEW.gst_collected);
        ELSE
            SET NEW.refund_amount = 0.00;
        END IF;
    ELSE
        SET NEW.refund_amount = 0.00;
    END IF;

    SET NEW.net_operating_profit = NEW.service_charge_amt - NEW.customer_id_payout;
END //

DELIMITER ;

-- PROCEDURES
DELIMITER //

CREATE PROCEDURE sp_ProcessBookingRequest(
    IN p_customer_id INT,
    IN p_pnr_number VARCHAR(10),
    IN p_train_number VARCHAR(10),
    IN p_travel_date DATE,
    IN p_travel_class VARCHAR(5),
    IN p_quota_type VARCHAR(20),
    IN p_slot_hour TINYINT,
    IN p_account_id INT,
    IN p_advance_paid DECIMAL(10,2),
    IN p_irctc_fare DECIMAL(10,2),
    IN p_status VARCHAR(10),
    IN p_wl_cat VARCHAR(10),
    IN p_wl_num INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
        IF p_advance_paid < p_irctc_fare THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Validation Failed: Advance must cover minimum IRCTC fare.';
        END IF;

        INSERT INTO Fact_Ticket_Bookings (
            customer_id, pnr_number, train_number, travel_date, travel_class,
            quota_type, booking_timestamp, booking_slot_hour, account_id,
            advance_paid, irctc_base_fare, booking_status, wl_category, 
            initial_wl_number, current_status
        ) VALUES (
            p_customer_id, p_pnr_number, p_train_number, p_travel_date, p_travel_class,
            p_quota_type, NOW(), p_slot_hour, p_account_id,
            p_advance_paid, p_irctc_fare, p_status, p_wl_cat,
            p_wl_num, p_status
        );
    COMMIT;
END //

DELIMITER ;

-- VIEWS
CREATE OR REPLACE VIEW vw_Daily24hOperatingSummary AS
SELECT 
    CAST(booking_timestamp AS DATE) AS operational_date,
    booking_slot_hour,
    CASE 
        WHEN booking_slot_hour = 8 THEN '08:00 AM (AC Tatkal Opening)'
        WHEN booking_slot_hour = 10 THEN '10:00 AM (Non-AC Tatkal Opening)'
        WHEN booking_slot_hour = 11 THEN '11:00 AM (General / Specials Opening)'
        ELSE 'Off-Peak Routine Hours'
    END AS operational_slot_type,
    COUNT(booking_id) AS total_tickets_booked,
    SUM(irctc_base_fare) AS total_railway_fare_routed,
    SUM(service_charge_amt) AS gross_service_fee,
    SUM(gst_collected) AS total_gst_collected,
    SUM(customer_id_payout) AS partner_id_commissions,
    SUM(refund_amount) AS total_refunds_processed,
    SUM(net_operating_profit) AS net_desk_profit
FROM Fact_Ticket_Bookings
GROUP BY CAST(booking_timestamp AS DATE), booking_slot_hour;

CREATE OR REPLACE VIEW vw_IRCTC_Account_Rankings AS
SELECT 
    acc.irctc_username,
    acc.account_type,
    acc.owner_name,
    COUNT(b.booking_id) AS total_bookings_handled,
    SUM(b.irctc_base_fare) AS total_volume_inr,
    SUM(b.net_operating_profit) AS total_agency_profit,
    SUM(b.customer_id_payout) AS total_owner_payout,
    DENSE_RANK() OVER (PARTITION BY acc.account_type ORDER BY SUM(b.net_operating_profit) DESC) AS rank_by_yield,
    ROW_NUMBER() OVER (ORDER BY COUNT(b.booking_id) DESC) AS overall_activity_rank
FROM Dim_IRCTC_Accounts acc
LEFT JOIN Fact_Ticket_Bookings b ON acc.account_id = b.account_id
GROUP BY acc.account_id, acc.irctc_username, acc.account_type, acc.owner_name;

-- SEED DATA
INSERT INTO Dim_Stations (station_code, station_name, division, zone, state) VALUES
('DRZ', 'Dalli Rajhara', 'Raipur', 'SECR', 'Chhattisgarh'),
('DURG', 'Durg Junction', 'Raipur', 'SECR', 'Chhattisgarh'),
('R', 'Raipur Junction', 'Raipur', 'SECR', 'Chhattisgarh'),
('G', 'Gondia Junction', 'Nagpur', 'SECR', 'Maharashtra'),
('BSP', 'Bilaspur Junction', 'Bilaspur', 'SECR', 'Chhattisgarh'),
('NZM', 'Hazrat Nizamuddin', 'Delhi', 'NR', 'Delhi');

INSERT INTO Dim_Trains (train_number, train_name, source_station, dest_station, route_via_dallirajhara) VALUES
('18207', 'Durg - Dalli Rajhara Express', 'DURG', 'DRZ', TRUE),
('18208', 'Dalli Rajhara - Durg Express', 'DRZ', 'DURG', TRUE),
('12823', 'Chhattisgarh Sampark Kranti', 'DURG', 'NZM', FALSE),
('18237', 'Chhattisgarh Express', 'G', 'NZM', FALSE),
('08815', 'Raipur - Keoti Passenger Special', 'R', 'DRZ', TRUE);

INSERT INTO Dim_IRCTC_Accounts (irctc_username, account_type, owner_name, owner_phone, commission_rate_pct) VALUES
('AGT_DRZ_MASTER', 'AGENT', 'Agency Head Desk', '9893011111', 0.00),
('CUST_TATKAL_01', 'CUSTOMER', 'Ramesh Verma (Dalli)', '9425211112', 25.00),
('CUST_TATKAL_02', 'CUSTOMER', 'Sunil Dewangan (Rajhara)', '9826111113', 25.00),
('CUST_TATKAL_03', 'CUSTOMER', 'Amit Sahu (Balod)', '9179011114', 30.00);

INSERT INTO Dim_Customers (full_name, mobile_number, city, state) VALUES
('Bhupendra Patel', '9988776601', 'Dalli Rajhara', 'Chhattisgarh'),
('Toman Lal Sinha', '9988776602', 'Dalli Rajhara', 'Chhattisgarh'),
('Prakash Chandrakar', '9988776603', 'Balod', 'Chhattisgarh'),
('Deepak Dewangan', '9988776604', 'Durg', 'Chhattisgarh');

INSERT INTO Fact_Ticket_Bookings 
(customer_id, pnr_number, train_number, travel_date, travel_class, quota_type, booking_timestamp, booking_slot_hour, account_id, advance_paid, irctc_base_fare, booking_status, wl_category, initial_wl_number, current_status)
VALUES
(1, '6245198231', '12823', '2026-11-10', '3A', 'TATKAL', '2026-11-02 10:00:15', 10, 2, 2500.00, 1850.00, 'CNF', 'NONE', 0, 'CNF/B2/45'),
(2, '6523981122', '12823', '2026-11-10', '2A', 'TATKAL', '2026-11-02 10:00:42', 10, 3, 3500.00, 2650.00, 'CNF', 'NONE', 0, 'CNF/A1/18'),
(3, '6891245533', '18237', '2026-11-12', 'SL', 'PREMIUM_TATKAL', '2026-11-02 11:01:05', 11, 4, 2000.00, 1220.00, 'CNF', 'NONE', 0, 'CNF/S4/23'),
(4, '6102938475', '18207', '2026-11-05', 'CC', 'GENERAL', '2026-11-02 15:30:10', 15, 1, 500.00, 380.00, 'CNF', 'NONE', 0, 'CNF/C1/12'),
(1, '6394857201', '12823', '2026-11-15', '3A', 'GENERAL', '2026-11-02 08:00:12', 8, 2, 2200.00, 1650.00, 'WL', 'GNWL', 14, 'WL/8');
