<?php
/**
 * Konfiguracja bazy danych - LogisticsERP
 *
 * WAŻNE: Dostosuj poniższe dane do swojej konfiguracji na serwerze 192.168.1.42
 */

define('DB_HOST', '192.168.1.42');
define('DB_NAME', 'logisticserp_dev');
define('DB_USER', 'logisticserp_dev');
define('DB_PASS', '4H8k7OGi%4F$#j6NFBoimCFB0tbGQHYm');

// Połączenie z bazą danych
function getDB() {
    try {
        $pdo = new PDO(
            "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME . ";charset=utf8mb4",
            DB_USER,
            DB_PASS,
            [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false,
            ]
        );
        return $pdo;
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Błąd połączenia z bazą danych']);
        exit;
    }
}

// Nagłówki CORS (pozwala na połączenia z aplikacji mobilnej)
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}
