-- =============================================================
-- Tabele do obsługi stanów magazynowych (przyjęcia / wydania)
-- Uruchom ten skrypt na serwerze 192.168.1.42 w bazie logisticserp
-- =============================================================

-- Stara tabela (zostawiamy dla historii, ale nie jest już używana)
-- CREATE TABLE IF NOT EXISTS `scanned_products` ( ... );

-- =============================================================
-- 1. Tabela ruchów magazynowych
-- =============================================================
CREATE TABLE IF NOT EXISTS `stock_movements` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `barcode` VARCHAR(128) NOT NULL,
    `code_type` ENUM('barcode','product_code') NOT NULL DEFAULT 'barcode',
    `product_name` VARCHAR(255) NOT NULL,
    `movement_type` ENUM('in','out') NOT NULL,
    `quantity` DECIMAL(10,2) NOT NULL,
    `unit` VARCHAR(20) NOT NULL DEFAULT 'szt',
    `note` VARCHAR(255) DEFAULT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_barcode` (`barcode`),
    INDEX `idx_movement_type` (`movement_type`),
    INDEX `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- 2. Widok podsumowania stanów magazynowych
-- =============================================================
CREATE OR REPLACE VIEW `stock_summary` AS
SELECT
    sm.barcode,
    sm.code_type,
    (SELECT sm2.product_name FROM stock_movements sm2
     WHERE sm2.barcode = sm.barcode ORDER BY sm2.created_at DESC LIMIT 1) AS product_name,
    sm.unit,
    COALESCE(SUM(CASE WHEN sm.movement_type = 'in' THEN sm.quantity ELSE 0 END), 0) AS total_in,
    COALESCE(SUM(CASE WHEN sm.movement_type = 'out' THEN sm.quantity ELSE 0 END), 0) AS total_out,
    COALESCE(SUM(CASE WHEN sm.movement_type = 'in' THEN sm.quantity ELSE 0 END), 0)
    - COALESCE(SUM(CASE WHEN sm.movement_type = 'out' THEN sm.quantity ELSE 0 END), 0) AS current_stock
FROM stock_movements sm
GROUP BY sm.barcode, sm.code_type, sm.unit;

-- =============================================================
-- Migracja z istniejącej bazy (uruchom ręcznie jeśli potrzebne):
-- =============================================================
-- INSERT INTO stock_movements (barcode, code_type, product_name, movement_type, quantity, unit, note, created_at)
-- SELECT barcode, code_type, product_name, 'in', quantity * scan_count, unit, 'Migracja ze starej tabeli', scanned_at
-- FROM scanned_products;

-- =============================================================
-- 3. Tabela dostaw (powiązanie z dokumentami WZ)
-- =============================================================
CREATE TABLE IF NOT EXISTS `stock_deliveries` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `document_number` VARCHAR(100) DEFAULT NULL,
    `document_date` DATE DEFAULT NULL,
    `supplier` VARCHAR(255) DEFAULT NULL,
    `document_type` VARCHAR(50) DEFAULT NULL,
    `items_count` INT NOT NULL DEFAULT 0,
    `user_id` INT DEFAULT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_supplier` (`supplier`),
    INDEX `idx_document_date` (`document_date`),
    INDEX `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dodanie kolumny delivery_id do stock_movements
ALTER TABLE `stock_movements` ADD COLUMN `delivery_id` INT DEFAULT NULL AFTER `note`;
ALTER TABLE `stock_movements` ADD INDEX `idx_delivery_id` (`delivery_id`);
