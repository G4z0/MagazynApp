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
    `user_id` INT DEFAULT NULL,
    `user_name` VARCHAR(100) DEFAULT NULL,
    `issue_reason` VARCHAR(50) DEFAULT NULL,
    `vehicle_plate` VARCHAR(20) DEFAULT NULL,
    `issue_target` VARCHAR(20) DEFAULT NULL,
    `driver_id` INT DEFAULT NULL,
    `driver_name` VARCHAR(100) DEFAULT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_barcode` (`barcode`),
    INDEX `idx_movement_type` (`movement_type`),
    INDEX `idx_created_at` (`created_at`),
    INDEX `idx_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- 2. Widok podsumowania stanów magazynowych
-- =============================================================
-- Definicja widoku znajduje się w sekcji 12, po utworzeniu `stock_products`,
-- aby nazwa i typ kodu pochodziły z kanonicznego słownika produktów.

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

-- =============================================================
-- 4. Migracja charset na utf8mb4 (polskie znaki, emoji itd.)
--    Uruchom jeśli tabele zostały utworzone z innym charset.
-- =============================================================
ALTER TABLE `stock_movements` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER TABLE `stock_deliveries` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

ALTER TABLE `stock_movements`
    MODIFY `product_name` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    MODIFY `note` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;

ALTER TABLE `stock_deliveries`
    MODIFY `supplier` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
    MODIFY `document_number` VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;

-- =============================================================
-- 5. Dodanie kolumn user_id i user_name do stock_movements
-- =============================================================
ALTER TABLE `stock_movements` ADD COLUMN `user_id` INT DEFAULT NULL AFTER `note`;
ALTER TABLE `stock_movements` ADD COLUMN `user_name` VARCHAR(100) DEFAULT NULL AFTER `user_id`;
ALTER TABLE `stock_movements` ADD INDEX `idx_user_id` (`user_id`);

-- =============================================================
-- 6. Dodanie kolumn issue_reason i vehicle_plate
-- =============================================================
ALTER TABLE `stock_movements` ADD COLUMN `issue_reason` VARCHAR(50) DEFAULT NULL AFTER `user_name`;
ALTER TABLE `stock_movements` ADD COLUMN `vehicle_plate` VARCHAR(20) DEFAULT NULL AFTER `issue_reason`;

-- =============================================================
-- 7. Dodanie kolumn issue_target, driver_id, driver_name
-- =============================================================
ALTER TABLE `stock_movements` ADD COLUMN `issue_target` VARCHAR(20) DEFAULT NULL AFTER `vehicle_plate`;
ALTER TABLE `stock_movements` ADD COLUMN `driver_id` INT DEFAULT NULL AFTER `issue_target`;
ALTER TABLE `stock_movements` ADD COLUMN `driver_name` VARCHAR(100) DEFAULT NULL AFTER `driver_id`;

-- =============================================================
-- 8. Minimalne stany magazynowe — używamy istniejącej tabeli
--    `stock_product_settings` (kolumna `min_quantity`).
--    Schemat referencyjny:
--      barcode VARCHAR(255), unit VARCHAR(50), min_quantity DECIMAL(10,2),
--      acknowledged, acknowledged_at, acknowledged_by,
--      updated_at, updated_by
--    UNIQUE KEY (barcode, unit)
-- =============================================================

-- =============================================================
-- 8. Tabela stock_products — słownik produktów + lokalizacja w magazynie
--    Regał: 1-2 wielkie litery (A..ZZ). Półka: 0 (podłoga) .. 99.
--    Slot identyfikowany jako "A0", "C3", "AB12" itd.
-- =============================================================
CREATE TABLE IF NOT EXISTS `stock_products` (
    `barcode`        VARCHAR(128) NOT NULL,
    `code_type`      ENUM('barcode','product_code') NOT NULL DEFAULT 'barcode',
    `product_name`   VARCHAR(255) NOT NULL,
    `unit`           VARCHAR(20) NOT NULL DEFAULT 'szt',
    `location_rack`  VARCHAR(2) DEFAULT NULL,
    `location_shelf` TINYINT UNSIGNED DEFAULT NULL,
    `created_at`     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`barcode`),
    KEY `idx_product_name` (`product_name`),
    KEY `idx_location` (`location_rack`, `location_shelf`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Backfill istniejących produktów z stock_movements (bez lokalizacji — NULL).
-- Bierzemy najnowszą nazwę/jednostkę/typ kodu dla każdego barcode.
INSERT IGNORE INTO `stock_products` (`barcode`, `code_type`, `product_name`, `unit`, `created_at`)
SELECT
    sm.barcode,
    sm.code_type,
    sm.product_name,
    sm.unit,
    MIN(sm.created_at)
FROM `stock_movements` sm
INNER JOIN (
    SELECT barcode, MAX(id) AS max_id
    FROM `stock_movements`
    GROUP BY barcode
) latest ON latest.max_id = sm.id
GROUP BY sm.barcode, sm.code_type, sm.product_name, sm.unit;

-- =============================================================
-- 9. Tabela stock_product_locations — wiele lokalizacji dla jednego produktu
--    Uwaga: pierwsza lokalizacja nadal jest kopiowana do stock_products,
--    żeby zachować zgodność ze starszymi klientami mobilnymi.
-- =============================================================
CREATE TABLE IF NOT EXISTS `stock_product_locations` (
        `id`             INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `barcode`        VARCHAR(128) NOT NULL,
        `location_rack`  VARCHAR(2) NOT NULL,
        `location_shelf` TINYINT UNSIGNED NOT NULL,
        `sort_order`     SMALLINT UNSIGNED NOT NULL DEFAULT 0,
        `created_at`     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `updated_at`     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        UNIQUE KEY `uniq_product_location` (`barcode`, `location_rack`, `location_shelf`),
        KEY `idx_product_sort` (`barcode`, `sort_order`),
        KEY `idx_location_lookup` (`location_rack`, `location_shelf`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Backfill z legacy kolumn stock_products.location_rack/location_shelf.
INSERT IGNORE INTO `stock_product_locations` (`barcode`, `location_rack`, `location_shelf`, `sort_order`)
SELECT
        sp.barcode,
        sp.location_rack,
        sp.location_shelf,
        0
FROM `stock_products` sp
WHERE sp.location_rack IS NOT NULL
    AND sp.location_shelf IS NOT NULL;

-- =============================================================
-- 10. Alias historycznych kodów produktu
--     Pozwala przepinać stare kody na aktualny rekord produktu
--     i zapobiega przypadkowemu odtworzeniu starego produktu.
-- =============================================================
CREATE TABLE IF NOT EXISTS `stock_product_aliases` (
    `alias_barcode`     VARCHAR(128) NOT NULL,
    `canonical_barcode` VARCHAR(128) NOT NULL,
    `created_at`        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`alias_barcode`),
    KEY `idx_canonical_barcode` (`canonical_barcode`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- 11. Audyt zmian nazwy i kodu produktu
--     Historia biznesowa jest zapisywana osobno, nawet jeśli ruchy
--     magazynowe są przepinane na nowy kod / nazwę.
-- =============================================================
CREATE TABLE IF NOT EXISTS `stock_product_change_log` (
    `id`                  INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `barcode`             VARCHAR(128) NOT NULL,
    `change_type`         ENUM('rename', 'change_barcode') NOT NULL,
    `previous_barcode`    VARCHAR(128) DEFAULT NULL,
    `new_barcode`         VARCHAR(128) DEFAULT NULL,
    `previous_name`       VARCHAR(255) DEFAULT NULL,
    `new_name`            VARCHAR(255) DEFAULT NULL,
    `changed_by_user_id`  INT DEFAULT NULL,
    `changed_by_user_name` VARCHAR(100) DEFAULT NULL,
    `changed_at`          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_change_barcode` (`barcode`),
    KEY `idx_change_type` (`change_type`),
    KEY `idx_changed_at` (`changed_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================
-- 12. Kanoniczny widok stanów magazynowych
--     Nazwa / typ kodu pochodzą ze słownika stock_products,
--     a nie z losowego MAX(product_name) z historii ruchów.
-- =============================================================
CREATE OR REPLACE VIEW `stock_summary` AS
SELECT
    sm.barcode,
    COALESCE(sp.code_type, MAX(sm.code_type)) AS code_type,
    COALESCE(sp.product_name, MAX(sm.product_name)) AS product_name,
    sm.unit,
    COALESCE(SUM(CASE WHEN sm.movement_type = 'in' THEN sm.quantity ELSE 0 END), 0) AS total_in,
    COALESCE(SUM(CASE WHEN sm.movement_type = 'out' THEN sm.quantity ELSE 0 END), 0) AS total_out,
    COALESCE(SUM(CASE WHEN sm.movement_type = 'in' THEN sm.quantity ELSE 0 END), 0)
    - COALESCE(SUM(CASE WHEN sm.movement_type = 'out' THEN sm.quantity ELSE 0 END), 0) AS current_stock
FROM stock_movements sm
LEFT JOIN stock_products sp ON sp.barcode = sm.barcode
GROUP BY sm.barcode, sm.unit, sp.code_type, sp.product_name;
