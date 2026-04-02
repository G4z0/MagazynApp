-- =============================================================
-- Tabela do przechowywania zeskanowanych kodów kreskowych
-- Uruchom ten skrypt na serwerze 192.168.1.42 w bazie logisticserp_dev
-- =============================================================

CREATE TABLE IF NOT EXISTS `scanned_products` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `barcode` VARCHAR(128) NOT NULL,
    `code_type` ENUM('barcode','product_code') NOT NULL DEFAULT 'barcode',
    `product_name` VARCHAR(255) NOT NULL,
    `quantity` DECIMAL(10,2) NOT NULL DEFAULT 1,
    `unit` VARCHAR(20) NOT NULL DEFAULT 'szt',
    `scanned_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_barcode` (`barcode`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Jeśli tabela już istnieje, dodaj nowe kolumny:
-- ALTER TABLE `scanned_products` ADD COLUMN `quantity` DECIMAL(10,2) NOT NULL DEFAULT 1 AFTER `product_name`;
-- ALTER TABLE `scanned_products` ADD COLUMN `unit` VARCHAR(20) NOT NULL DEFAULT 'szt' AFTER `quantity`;
-- ALTER TABLE `scanned_products` ADD COLUMN `code_type` ENUM('barcode','product_code') NOT NULL DEFAULT 'barcode' AFTER `barcode`;
