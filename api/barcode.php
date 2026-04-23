<?php
/**
 * API endpoint do obsługi ruchów magazynowych
 *
 * Endpointy:
 *   POST /barcode.php             - Zarejestruj ruch magazynowy (przyjęcie/wydanie)
 *   GET  /barcode.php?barcode=X   - Pobierz stan magazynowy i historię ruchów
 *   GET  /barcode.php?next_sas=1  - Pobierz następny wolny kod SAS-N
 */

require_once __DIR__ . '/config.php';

$db = getDB();
$method = $_SERVER['REQUEST_METHOD'];

/**
 * Waliduje wejście lokalizacji.
 * Zwraca [rack|null, shelf|null] lub rzuca InvalidArgumentException z opisem błędu.
 *
 * Reguły:
 *   - oba puste/null  → [null, null] (brak lokalizacji)
 *   - rack: 1-2 wielkie litery A-Z (np. "A", "AB")
 *   - shelf: 0-99
 *   - jeśli podany rack, shelf też musi być (i odwrotnie)
 */
function normalizeLocation($rackRaw, $shelfRaw) {
    $hasRack  = $rackRaw !== null && $rackRaw !== '';
    $hasShelf = $shelfRaw !== null && $shelfRaw !== '';

    if (!$hasRack && !$hasShelf) {
        return [null, null];
    }
    if ($hasRack !== $hasShelf) {
        throw new InvalidArgumentException('Lokalizacja wymaga obu pól: regał i półka');
    }

    $rack = strtoupper(trim((string)$rackRaw));
    if (!preg_match('/^[A-Z]{1,2}$/', $rack)) {
        throw new InvalidArgumentException('Regał musi być 1-2 wielkimi literami A-Z');
    }

    if (!is_numeric($shelfRaw)) {
        throw new InvalidArgumentException('Półka musi być liczbą 0-99');
    }
    $shelf = (int)$shelfRaw;
    if ($shelf < 0 || $shelf > 99) {
        throw new InvalidArgumentException('Półka musi być w zakresie 0-99');
    }

    return [$rack, $shelf];
}

/**
 * UPSERT do stock_products. Wywoływane po INSERT do stock_movements.
 * Aktualizuje nazwę/jednostkę/typ kodu (najnowszy wpis wygrywa).
 * Lokalizacja jest aktualizowana TYLKO jeśli przekazana (nie nadpisuje na NULL przy zwykłym ruchu).
 */
function upsertStockProduct($db, $barcode, $codeType, $productName, $unit, $locationRack = null, $locationShelf = null) {
    if ($locationRack !== null && $locationShelf !== null) {
        $stmt = $db->prepare("
            INSERT INTO stock_products (barcode, code_type, product_name, unit, location_rack, location_shelf)
            VALUES (:barcode, :code_type, :product_name, :unit, :rack, :shelf)
            ON DUPLICATE KEY UPDATE
                code_type = VALUES(code_type),
                product_name = VALUES(product_name),
                unit = VALUES(unit),
                location_rack = VALUES(location_rack),
                location_shelf = VALUES(location_shelf)
        ");
        $stmt->execute([
            ':barcode' => $barcode,
            ':code_type' => $codeType,
            ':product_name' => $productName,
            ':unit' => $unit,
            ':rack' => $locationRack,
            ':shelf' => $locationShelf,
        ]);
    } else {
        $stmt = $db->prepare("
            INSERT INTO stock_products (barcode, code_type, product_name, unit)
            VALUES (:barcode, :code_type, :product_name, :unit)
            ON DUPLICATE KEY UPDATE
                code_type = VALUES(code_type),
                product_name = VALUES(product_name),
                unit = VALUES(unit)
        ");
        $stmt->execute([
            ':barcode' => $barcode,
            ':code_type' => $codeType,
            ':product_name' => $productName,
            ':unit' => $unit,
        ]);
    }
}

/**
 * Normalizuje listę lokalizacji produktu.
 *
 * Każdy wpis ma postać: ['rack' => 'A', 'shelf' => 3]
 * Puste wpisy są ignorowane, duplikaty są usuwane z zachowaniem kolejności.
 */
function normalizeLocations($locationsRaw) {
    if ($locationsRaw === null) {
        return [];
    }

    if (!is_array($locationsRaw)) {
        throw new InvalidArgumentException('Pole locations musi być tablicą');
    }

    $normalized = [];
    $seen = [];

    foreach ($locationsRaw as $entry) {
        if (!is_array($entry)) {
            throw new InvalidArgumentException('Każda lokalizacja musi zawierać regał i półkę');
        }

        [$rack, $shelf] = normalizeLocation(
            $entry['rack'] ?? null,
            $entry['shelf'] ?? null
        );

        if ($rack === null || $shelf === null) {
            continue;
        }

        $key = $rack . '#' . $shelf;
        if (isset($seen[$key])) {
            continue;
        }

        $seen[$key] = true;
        $normalized[] = [
            'rack' => $rack,
            'shelf' => $shelf,
        ];
    }

    return $normalized;
}

/**
 * Wspiera zarówno nowy format `locations: [{rack, shelf}, ...]`,
 * jak i legacy `location_rack` + `location_shelf`.
 */
function extractRequestedLocations($input) {
    if (array_key_exists('locations', $input)) {
        return normalizeLocations($input['locations']);
    }

    [$rack, $shelf] = normalizeLocation(
        $input['location_rack'] ?? null,
        $input['location_shelf'] ?? null
    );

    if ($rack === null || $shelf === null) {
        return [];
    }

    return [[
        'rack' => $rack,
        'shelf' => $shelf,
    ]];
}

function tableExists($db, $tableName) {
    static $exists = [];

    if (array_key_exists($tableName, $exists)) {
        return $exists[$tableName];
    }

    if (!preg_match('/^[A-Za-z0-9_]+$/', $tableName)) {
        $exists[$tableName] = false;
        return false;
    }

    try {
        $db->query("SELECT 1 FROM `{$tableName}` LIMIT 1");
        $exists[$tableName] = true;
    } catch (PDOException $e) {
        $exists[$tableName] = false;
    }

    return $exists[$tableName];
}

function stockProductLocationsTableExists($db) {
    return tableExists($db, 'stock_product_locations');
}

function stockProductsTableExists($db) {
    return tableExists($db, 'stock_products');
}

function stockProductAliasesTableExists($db) {
    return tableExists($db, 'stock_product_aliases');
}

function stockProductChangeLogTableExists($db) {
    return tableExists($db, 'stock_product_change_log');
}

function resolveCanonicalBarcode($db, $barcode) {
    $current = trim((string)$barcode);
    if ($current === '' || !stockProductAliasesTableExists($db)) {
        return $current;
    }

    $seen = [];

    while ($current !== '' && !isset($seen[$current])) {
        $seen[$current] = true;

        $stmt = $db->prepare("SELECT canonical_barcode FROM stock_product_aliases WHERE alias_barcode = ? LIMIT 1");
        $stmt->execute([$current]);
        $next = $stmt->fetchColumn();

        if (!is_string($next)) {
            break;
        }

        $next = trim($next);
        if ($next === '' || $next === $current) {
            break;
        }

        $current = $next;
    }

    return $current;
}

function detectCodeType($barcode) {
    $trimmed = trim((string)$barcode);
    if (preg_match('/^\d{8,13}$/', $trimmed)) {
        return 'barcode';
    }

    return 'product_code';
}

function appendProductSearchCondition($db, &$sql, array &$params, $search, $productNameExpression, $barcodeExpression) {
    if ($search === '') {
        return;
    }

    $searchParam = '%' . $search . '%';
    $conditions = [
        $productNameExpression . ' LIKE ?',
        $barcodeExpression . ' LIKE ?',
    ];
    $params[] = $searchParam;
    $params[] = $searchParam;

    if (stockProductAliasesTableExists($db)) {
        $conditions[] = "EXISTS (
            SELECT 1
            FROM stock_product_aliases spa
            WHERE spa.canonical_barcode = {$barcodeExpression}
              AND spa.alias_barcode LIKE ?
        )";
        $params[] = $searchParam;
    }

    $sql .= ' WHERE (' . implode(' OR ', $conditions) . ')';
}

function getProductSnapshot($db, $barcode) {
    $barcode = trim((string)$barcode);
    if ($barcode === '') {
        return null;
    }

    if (stockProductsTableExists($db)) {
        $stmt = $db->prepare("
            SELECT barcode, code_type, product_name, unit
            FROM stock_products
            WHERE barcode = ?
            LIMIT 1
        ");
        $stmt->execute([$barcode]);
        $row = $stmt->fetch();
        if ($row) {
            return $row;
        }
    }

    $stmt = $db->prepare("
        SELECT barcode, code_type, product_name, unit
        FROM stock_movements
        WHERE barcode = ?
        ORDER BY created_at DESC, id DESC
        LIMIT 1
    ");
    $stmt->execute([$barcode]);
    $row = $stmt->fetch();

    return $row ?: null;
}

function syncBarcodeAliasesAfterChange($db, $oldBarcode, $newBarcode) {
    if (!stockProductAliasesTableExists($db)) {
        return;
    }

    $stmt = $db->prepare("
        UPDATE stock_product_aliases
        SET canonical_barcode = ?, updated_at = CURRENT_TIMESTAMP
        WHERE canonical_barcode = ?
    ");
    $stmt->execute([$newBarcode, $oldBarcode]);

    $stmt = $db->prepare("
        INSERT INTO stock_product_aliases (alias_barcode, canonical_barcode)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE
            canonical_barcode = VALUES(canonical_barcode),
            updated_at = CURRENT_TIMESTAMP
    ");
    $stmt->execute([$oldBarcode, $newBarcode]);
}

function insertProductChangeLog(
    $db,
    $changeType,
    $barcode,
    $previousBarcode,
    $newBarcode,
    $previousName,
    $newName,
    $userId,
    $userName
) {
    if (!stockProductChangeLogTableExists($db)) {
        return;
    }

    if ($userName !== null && mb_strlen($userName) > 100) {
        $userName = mb_substr($userName, 0, 100);
    }

    $stmt = $db->prepare("
        INSERT INTO stock_product_change_log (
            barcode,
            change_type,
            previous_barcode,
            new_barcode,
            previous_name,
            new_name,
            changed_by_user_id,
            changed_by_user_name
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ");
    $stmt->execute([
        $barcode,
        $changeType,
        $previousBarcode,
        $newBarcode,
        $previousName,
        $newName,
        $userId,
        $userName,
    ]);
}

/**
 * Zwraca listę lokalizacji produktu.
 *
 * Najpierw korzysta z tabeli stock_product_locations, a jeśli ta nie istnieje
 * albo produkt nie ma jeszcze wpisów, robi fallback do legacy kolumn
 * stock_products.location_rack/location_shelf.
 */
function getProductLocations($db, $barcode) {
    if (stockProductLocationsTableExists($db)) {
        $stmt = $db->prepare("
            SELECT location_rack, location_shelf
            FROM stock_product_locations
            WHERE barcode = ?
            ORDER BY sort_order ASC, id ASC
        ");
        $stmt->execute([$barcode]);
        $rows = $stmt->fetchAll();

        if (!empty($rows)) {
            return array_map(function ($row) {
                return [
                    'rack' => $row['location_rack'],
                    'shelf' => (int)$row['location_shelf'],
                ];
            }, $rows);
        }
    }

    try {
        $stmt = $db->prepare("
            SELECT location_rack, location_shelf
            FROM stock_products
            WHERE barcode = ?
            LIMIT 1
        ");
        $stmt->execute([$barcode]);
        $row = $stmt->fetch();
    } catch (PDOException $e) {
        return [];
    }

    if (!$row || $row['location_rack'] === null || $row['location_shelf'] === null) {
        return [];
    }

    return [[
        'rack' => $row['location_rack'],
        'shelf' => (int)$row['location_shelf'],
    ]];
}

/**
 * Zwraca mapę barcode => lista lokalizacji. Używane do list/lookup bez N+1.
 */
function getLocationsMapForBarcodes($db, $barcodes) {
    $map = [];

    if (empty($barcodes)) {
        return $map;
    }

    $uniqueBarcodes = array_values(array_unique(array_filter($barcodes, function ($barcode) {
        return is_string($barcode) && $barcode !== '';
    })));

    if (empty($uniqueBarcodes)) {
        return $map;
    }

    foreach ($uniqueBarcodes as $barcode) {
        $map[$barcode] = [];
    }

    if (stockProductLocationsTableExists($db)) {
        $placeholders = implode(',', array_fill(0, count($uniqueBarcodes), '?'));
        $stmt = $db->prepare("
            SELECT barcode, location_rack, location_shelf
            FROM stock_product_locations
            WHERE barcode IN ($placeholders)
            ORDER BY barcode ASC, sort_order ASC, id ASC
        ");
        $stmt->execute($uniqueBarcodes);

        foreach ($stmt->fetchAll() as $row) {
            $map[$row['barcode']][] = [
                'rack' => $row['location_rack'],
                'shelf' => (int)$row['location_shelf'],
            ];
        }
    }

    $missing = array_values(array_filter($uniqueBarcodes, function ($barcode) use ($map) {
        return empty($map[$barcode]);
    }));

    if (!empty($missing)) {
        try {
            $placeholders = implode(',', array_fill(0, count($missing), '?'));
            $stmt = $db->prepare("
                SELECT barcode, location_rack, location_shelf
                FROM stock_products
                WHERE barcode IN ($placeholders)
            ");
            $stmt->execute($missing);

            foreach ($stmt->fetchAll() as $row) {
                if ($row['location_rack'] === null || $row['location_shelf'] === null) {
                    continue;
                }
                $map[$row['barcode']] = [[
                    'rack' => $row['location_rack'],
                    'shelf' => (int)$row['location_shelf'],
                ]];
            }
        } catch (PDOException $e) {
            // Legacy tabela może nie istnieć jeszcze przy częściowych migracjach.
        }
    }

    return $map;
}

/**
 * Zapisuje pełną listę lokalizacji produktu.
 *
 * Dla zgodności ze starszymi klientami pierwsza lokalizacja jest też kopiowana
 * do legacy kolumn stock_products.location_rack/location_shelf.
 */
function saveProductLocations($db, $barcode, $locations) {
    $primary = !empty($locations) ? $locations[0] : null;
    $primaryRack = $primary['rack'] ?? null;
    $primaryShelf = $primary['shelf'] ?? null;

    if (stockProductLocationsTableExists($db)) {
        $stmt = $db->prepare("DELETE FROM stock_product_locations WHERE barcode = ?");
        $stmt->execute([$barcode]);

        if (!empty($locations)) {
            $stmt = $db->prepare("
                INSERT INTO stock_product_locations (barcode, location_rack, location_shelf, sort_order)
                VALUES (?, ?, ?, ?)
            ");

            foreach ($locations as $index => $location) {
                $stmt->execute([
                    $barcode,
                    $location['rack'],
                    $location['shelf'],
                    $index,
                ]);
            }
        }
    } elseif (count($locations) > 1) {
        throw new PDOException('Aby zapisać więcej niż jedną lokalizację, uruchom migrację tabeli stock_product_locations.');
    }

    try {
        $stmt = $db->prepare("
            UPDATE stock_products
            SET location_rack = ?, location_shelf = ?
            WHERE barcode = ?
        ");
        $stmt->execute([$primaryRack, $primaryShelf, $barcode]);
    } catch (PDOException $e) {
        // stock_products może jeszcze nie istnieć w świeżo migrowanym środowisku.
    }
}

switch ($method) {
    case 'POST':
        handlePost($db);
        break;
    case 'GET':
        handleGet($db);
        break;
    case 'PUT':
        handlePut($db);
        break;
    default:
        http_response_code(405);
        echo json_encode(['error' => 'Metoda niedozwolona']);
}

/**
 * POST - Zarejestruj ruch magazynowy (przyjęcie lub wydanie)
 *
 * Body (JSON):
 *   {
 *     "barcode": "5901234123457",
 *     "product_name": "Nazwa produktu",
 *     "movement_type": "in",         // "in" lub "out"
 *     "quantity": 5,
 *     "unit": "szt",
 *     "code_type": "barcode",
 *     "note": "Mechanik Kowalski",    // opcjonalne
 *     "user_id": 5,                    // opcjonalne — ID użytkownika
 *     "user_name": "Jan Kowalski"      // opcjonalne — nazwa użytkownika
 *   }
 */
function handlePost($db) {
    $input = json_decode(file_get_contents('php://input'), true);

    // Walidacja wymaganych pól
    if (empty($input['barcode']) || empty($input['product_name'])) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'error' => 'Wymagane pola: barcode, product_name'
        ]);
        return;
    }

    $barcode = trim($input['barcode']);
    $productName = trim($input['product_name']);
    $quantity = isset($input['quantity']) ? (float)$input['quantity'] : 1;
    $unit = trim($input['unit'] ?? 'szt');
    $codeType = trim($input['code_type'] ?? 'barcode');
    $movementType = trim($input['movement_type'] ?? 'in');
    $note = isset($input['note']) ? trim($input['note']) : null;
    $userId = isset($input['user_id']) ? (int)$input['user_id'] : null;
    $userName = isset($input['user_name']) ? trim($input['user_name']) : null;
    $issueReason = isset($input['issue_reason']) ? trim($input['issue_reason']) : null;
    $vehiclePlate = isset($input['vehicle_plate']) ? trim($input['vehicle_plate']) : null;
    $issueTarget = isset($input['issue_target']) ? trim($input['issue_target']) : null;
    $driverId = isset($input['driver_id']) ? (int)$input['driver_id'] : null;
    $driverName = isset($input['driver_name']) ? trim($input['driver_name']) : null;
    $minQuantity = (isset($input['min_quantity']) && $input['min_quantity'] !== '' && $input['min_quantity'] !== null)
        ? (float)$input['min_quantity']
        : null;

    $barcode = resolveCanonicalBarcode($db, $barcode);
    $existingProduct = getProductSnapshot($db, $barcode);
    if ($existingProduct) {
        $productName = $existingProduct['product_name'] ?? $productName;
        $codeType = $existingProduct['code_type'] ?? $codeType;
    }

    // Lokalizacje (opcjonalnie). Wspieramy zarówno nową listę `locations`,
    // jak i legacy parę `location_rack` + `location_shelf`.
    try {
        $locations = extractRequestedLocations($input);
    } catch (InvalidArgumentException $e) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => $e->getMessage()]);
        return;
    }

    // Walidacja typu kodu
    if (!in_array($codeType, ['barcode', 'product_code'], true)) {
        $codeType = 'barcode';
    }

    // Walidacja typu ruchu
    if (!in_array($movementType, ['in', 'out'], true)) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'error' => 'Typ ruchu musi być "in" (przyjęcie) lub "out" (wydanie)'
        ]);
        return;
    }

    // Walidacja ilości
    if ($quantity <= 0) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'error' => 'Ilość musi być większa od 0'
        ]);
        return;
    }

    // Walidacja jednostki
    $allowedUnits = ['szt', 'l', 'kg', 'm', 'opak', 'kpl'];
    if (!in_array($unit, $allowedUnits, true)) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'error' => 'Niedozwolona jednostka. Dozwolone: ' . implode(', ', $allowedUnits)
        ]);
        return;
    }

    // Przy wydaniu sprawdź czy jest wystarczający stan
    if ($movementType === 'out') {
        $stmt = $db->prepare("
            SELECT
                COALESCE(SUM(CASE WHEN movement_type = 'in' THEN quantity ELSE 0 END), 0)
                - COALESCE(SUM(CASE WHEN movement_type = 'out' THEN quantity ELSE 0 END), 0) AS current_stock
            FROM stock_movements
            WHERE barcode = ? AND unit = ?
        ");
        $stmt->execute([$barcode, $unit]);
        $row = $stmt->fetch();
        $currentStock = (float)($row['current_stock'] ?? 0);

        if ($currentStock < $quantity) {
            http_response_code(400);
            echo json_encode([
                'success' => false,
                'error' => 'Niewystarczający stan magazynowy. Dostępne: ' . $currentStock . ' ' . $unit
            ]);
            return;
        }
    }

    // Walidacja powodu wydania
    if ($issueReason !== null && !in_array($issueReason, ['departure', 'replacement'], true)) {
        $issueReason = null;
    }

    // Walidacja celu wydania
    if ($issueTarget !== null && !in_array($issueTarget, ['vehicle', 'driver'], true)) {
        $issueTarget = null;
    }

    // Ograniczenie długości nazwy kierowcy
    if ($driverName !== null && mb_strlen($driverName) > 100) {
        $driverName = mb_substr($driverName, 0, 100);
    }

    // Ograniczenie długości tablicy rejestracyjnej
    if ($vehiclePlate !== null && mb_strlen($vehiclePlate) > 20) {
        $vehiclePlate = mb_substr($vehiclePlate, 0, 20);
    }

    // Ograniczenie długości notatki
    if ($note !== null && mb_strlen($note) > 255) {
        $note = mb_substr($note, 0, 255);
    }

    // Zapisz ruch magazynowy
    try {
        $stmt = $db->prepare("
            INSERT INTO stock_movements (barcode, code_type, product_name, movement_type, quantity, unit, note, user_id, user_name, issue_reason, vehicle_plate, issue_target, driver_id, driver_name)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ");
        $stmt->execute([$barcode, $codeType, $productName, $movementType, $quantity, $unit, $note, $userId, $userName, $issueReason, $vehiclePlate, $issueTarget, $driverId, $driverName]);
    } catch (PDOException $e) {
        // Fallback: kolumny issue_target/driver_id/driver_name jeszcze nie istnieją
        $stmt = $db->prepare("
            INSERT INTO stock_movements (barcode, code_type, product_name, movement_type, quantity, unit, note, user_id, user_name, issue_reason, vehicle_plate)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ");
        $stmt->execute([$barcode, $codeType, $productName, $movementType, $quantity, $unit, $note, $userId, $userName, $issueReason, $vehiclePlate]);
    }
    $newId = $db->lastInsertId();

    // Synchronizuj słownik produktów (stock_products). Lokalizacja nadpisywana
    // tylko jeśli przekazana — zwykłe ruchy magazynowe nie czyszczą jej.
    try {
        $primaryLocation = !empty($locations) ? $locations[0] : null;
        upsertStockProduct(
            $db,
            $barcode,
            $codeType,
            $productName,
            $unit,
            $primaryLocation['rack'] ?? null,
            $primaryLocation['shelf'] ?? null
        );

        if (!empty($locations)) {
            saveProductLocations($db, $barcode, $locations);
        }
    } catch (PDOException $e) {
        // Tabela stock_products jeszcze nie istnieje — nie blokuj zapisu ruchu.
        // (Wymagana migracja: api/setup_database.sql sekcja 8/9.)
    }

    // Upsert minimalnego stanu (opcjonalnie). Tylko jeśli klient go podał.
    if ($minQuantity !== null && $minQuantity >= 0) {
        try {
            $stmt = $db->prepare("
                INSERT INTO stock_product_settings (barcode, unit, min_quantity, updated_at, updated_by)
                VALUES (?, ?, ?, NOW(), ?)
                ON DUPLICATE KEY UPDATE
                    min_quantity = VALUES(min_quantity),
                    updated_at = NOW(),
                    updated_by = VALUES(updated_by)
            ");
            $stmt->execute([$barcode, $unit, $minQuantity, $userId]);
        } catch (PDOException $e) {
            // Tabela jeszcze nie istnieje — nie blokuj zapisu ruchu.
        }
    }

    $label = $movementType === 'in' ? 'Przyjęto' : 'Wydano';

    http_response_code(201);
    echo json_encode([
        'success' => true,
        'message' => $label . ' ' . $quantity . ' ' . $unit,
        'data' => [
            'id' => (int)$newId,
            'barcode' => $barcode,
            'code_type' => $codeType,
            'product_name' => $productName,
            'movement_type' => $movementType,
            'quantity' => $quantity,
            'unit' => $unit,
            'note' => $note,
        ]
    ]);
}

/**
 * GET - Pobierz stan magazynowy i historię ruchów
 *
 * Parametry URL:
 *   ?barcode=5901234123457  - Pobierz stan i historię konkretnego produktu
 *   ?list=1                - Pobierz listę wszystkich produktów ze stanami
 *   ?list=1&search=nazwa   - Szukaj po nazwie produktu lub kodzie
 *   ?parts=1               - Pobierz dostępne części (stan > 0), opcja ?search=
 *   ?low_stock=1           - Produkty z zerowym lub niskim stanem
 */
function handleGet($db) {
    // Lookup lokalizacji produktu po barcode (funkcja "lupa")
    if (isset($_GET['location'])) {
        $barcode = trim($_GET['location']);
        if ($barcode === '') {
            http_response_code(400);
            echo json_encode(['success' => false, 'error' => 'Parametr location jest wymagany']);
            return;
        }

        $barcode = resolveCanonicalBarcode($db, $barcode);
        $row = getProductSnapshot($db, $barcode);
        if (!$row) {
            echo json_encode(['success' => true, 'exists' => false, 'product' => null]);
            return;
        }

        $locations = getProductLocations($db, $barcode);
        $primary = !empty($locations) ? $locations[0] : null;

        echo json_encode([
            'success' => true,
            'exists' => true,
            'product' => [
                'barcode' => $row['barcode'],
                'product_name' => $row['product_name'],
                'unit' => $row['unit'],
                'location_rack' => $primary['rack'] ?? null,
                'location_shelf' => $primary['shelf'] ?? null,
                'locations' => $locations,
                'locations_count' => count($locations),
            ],
        ]);
        return;
    }

    // Pobierz listę kierowców (aktywnych pracowników)
    if (isset($_GET['drivers'])) {
        $search = isset($_GET['search']) ? trim($_GET['search']) : '';
        
        $query = "
            SELECT e.id, e.firstname, e.secondname, e.lastname
            FROM employees e
            WHERE e.deleted = 0
              AND e.not_arrive = 0
              AND e.cancelled = 0
              AND (e.date_of_dismissal IS NULL OR e.date_of_dismissal > CURDATE())
        ";
        $params = [];
        
        if ($search !== '') {
            $query .= " AND (CONCAT(e.firstname, ' ', e.lastname) LIKE ? OR CONCAT(e.lastname, ' ', e.firstname) LIKE ?)";
            $searchParam = '%' . $search . '%';
            $params[] = $searchParam;
            $params[] = $searchParam;
        }
        
        $query .= " ORDER BY e.lastname ASC, e.firstname ASC";
        
        $stmt = $db->prepare($query);
        $stmt->execute($params);
        $drivers = $stmt->fetchAll(PDO::FETCH_ASSOC);
        
        $result = [];
        foreach ($drivers as $d) {
            $fullName = trim($d['firstname'] . ' ' . $d['lastname']);
            $result[] = [
                'id' => (int)$d['id'],
                'name' => $fullName,
            ];
        }
        
        echo json_encode(['success' => true, 'drivers' => $result]);
        return;
    }

    // Generuj następny wolny kod SAS-N
    if (isset($_GET['next_sas'])) {
        $stmt = $db->prepare("
            SELECT barcode FROM stock_movements
            WHERE barcode LIKE 'SAS-%'
            ORDER BY CAST(SUBSTRING(barcode, 5) AS UNSIGNED) DESC
            LIMIT 1
        ");
        $stmt->execute();
        $row = $stmt->fetch();

        $nextNum = 1;
        if ($row) {
            $lastNum = (int)substr($row['barcode'], 4);
            $nextNum = $lastNum + 1;
        }

        echo json_encode([
            'success' => true,
            'next_code' => 'SAS-' . $nextNum,
        ]);
        return;
    }

    // Alerty niskiego stanu — używamy per-produktowego min_quantity
    // (fallback: < 5, gdy brak ustawienia / tabela nie istnieje).
    if (isset($_GET['low_stock'])) {
        try {
            $stmt = $db->prepare("
                SELECT
                    sm.barcode,
                    COALESCE(sp.product_name, MAX(sm.product_name)) AS product_name,
                    sm.unit,
                    COALESCE(SUM(CASE WHEN sm.movement_type = 'in' THEN sm.quantity ELSE 0 END), 0)
                    - COALESCE(SUM(CASE WHEN sm.movement_type = 'out' THEN sm.quantity ELSE 0 END), 0) AS current_stock,
                    sps.min_quantity
                FROM stock_movements sm
                LEFT JOIN stock_products sp ON sp.barcode = sm.barcode
                LEFT JOIN stock_product_settings sps
                       ON sps.barcode = sm.barcode AND sps.unit = sm.unit
                GROUP BY sm.barcode, sm.unit, sps.min_quantity, sp.product_name
                HAVING current_stock < COALESCE(sps.min_quantity, 5)
                   AND COALESCE(sps.min_quantity, 5) > 0
                ORDER BY current_stock ASC, product_name ASC
                LIMIT 50
            ");
            $stmt->execute();
            $items = $stmt->fetchAll();
        } catch (PDOException $e) {
            // Fallback bez tabeli stock_product_settings
            $stmt = $db->prepare("
                SELECT
                    barcode,
                    MAX(product_name) AS product_name,
                    unit,
                    COALESCE(SUM(CASE WHEN movement_type = 'in' THEN quantity ELSE 0 END), 0)
                    - COALESCE(SUM(CASE WHEN movement_type = 'out' THEN quantity ELSE 0 END), 0) AS current_stock,
                    NULL AS min_quantity
                FROM stock_movements
                GROUP BY barcode, unit
                HAVING current_stock < 5
                ORDER BY current_stock ASC, MAX(product_name) ASC
                LIMIT 20
            ");
            $stmt->execute();
            $items = $stmt->fetchAll();
        }

        echo json_encode(['success' => true, 'items' => $items]);
        return;
    }

    // Lista dostępnych części (stan > 0) — do wyboru w formularzu naprawy
    if (isset($_GET['parts'])) {
        $search = isset($_GET['search']) ? trim($_GET['search']) : '';

        $sql = "
            SELECT
                sm.barcode,
                COALESCE(sp.product_name, MAX(sm.product_name)) AS product_name,
                sm.unit,
                COALESCE(SUM(CASE WHEN sm.movement_type = 'in' THEN sm.quantity ELSE 0 END), 0)
                - COALESCE(SUM(CASE WHEN sm.movement_type = 'out' THEN sm.quantity ELSE 0 END), 0) AS current_stock,
                sp.location_rack,
                sp.location_shelf
            FROM stock_movements sm
            LEFT JOIN stock_products sp ON sp.barcode = sm.barcode
        ";
        $params = [];

        appendProductSearchCondition(
            $db,
            $sql,
            $params,
            $search,
            'COALESCE(sp.product_name, sm.product_name)',
            'sm.barcode'
        );

        $sql .= " GROUP BY sm.barcode, sm.unit, sp.product_name, sp.location_rack, sp.location_shelf
                   HAVING current_stock > 0
               ORDER BY product_name ASC";

        try {
            $stmt = $db->prepare($sql);
            $stmt->execute($params);
            $parts = $stmt->fetchAll();
        } catch (PDOException $e) {
            // Fallback: tabela stock_products jeszcze nie istnieje
            $sqlFallback = "
                SELECT
                    barcode,
                    MAX(product_name) AS product_name,
                    unit,
                    COALESCE(SUM(CASE WHEN movement_type = 'in' THEN quantity ELSE 0 END), 0)
                    - COALESCE(SUM(CASE WHEN movement_type = 'out' THEN quantity ELSE 0 END), 0) AS current_stock,
                    NULL AS location_rack,
                    NULL AS location_shelf
                FROM stock_movements
            ";
            $fallbackParams = [];
            appendProductSearchCondition(
                $db,
                $sqlFallback,
                $fallbackParams,
                $search,
                'product_name',
                'barcode'
            );
            $sqlFallback .= " GROUP BY barcode, unit
                               HAVING current_stock > 0
                               ORDER BY MAX(product_name) ASC";
            $stmt = $db->prepare($sqlFallback);
            $stmt->execute($fallbackParams);
            $parts = $stmt->fetchAll();
        }

        $locationsMap = getLocationsMapForBarcodes($db, array_column($parts, 'barcode'));
        foreach ($parts as &$part) {
            $locations = $locationsMap[$part['barcode']] ?? [];
            $part['locations'] = $locations;
            $part['locations_count'] = count($locations);
            if (!empty($locations)) {
                $part['location_rack'] = $locations[0]['rack'];
                $part['location_shelf'] = $locations[0]['shelf'];
            }
        }
        unset($part);

        echo json_encode(['success' => true, 'parts' => $parts]);
        return;
    }

    // Lista wszystkich produktów ze stanami
    if (isset($_GET['list'])) {
        $search = isset($_GET['search']) ? trim($_GET['search']) : '';

        $sql = "
            SELECT
                sm.barcode,
                COALESCE(sp.product_name, MAX(sm.product_name)) AS product_name,
                COALESCE(sp.code_type, MAX(sm.code_type)) AS code_type,
                sm.unit,
                COALESCE(SUM(CASE WHEN sm.movement_type = 'in' THEN sm.quantity ELSE 0 END), 0) AS total_in,
                COALESCE(SUM(CASE WHEN sm.movement_type = 'out' THEN sm.quantity ELSE 0 END), 0) AS total_out,
                COALESCE(SUM(CASE WHEN sm.movement_type = 'in' THEN sm.quantity ELSE 0 END), 0)
                - COALESCE(SUM(CASE WHEN sm.movement_type = 'out' THEN sm.quantity ELSE 0 END), 0) AS current_stock,
                MAX(sm.created_at) AS last_movement,
                sp.location_rack,
                sp.location_shelf,
                sps.min_quantity
            FROM stock_movements sm
            LEFT JOIN stock_products sp ON sp.barcode = sm.barcode
            LEFT JOIN stock_product_settings sps
                   ON sps.barcode = sm.barcode AND sps.unit = sm.unit
        ";
        $params = [];

        appendProductSearchCondition(
            $db,
            $sql,
            $params,
            $search,
            'COALESCE(sp.product_name, sm.product_name)',
            'sm.barcode'
        );

        $sql .= " GROUP BY sm.barcode, sm.unit, sp.product_name, sp.code_type, sp.location_rack, sp.location_shelf, sps.min_quantity ORDER BY MAX(sm.created_at) DESC";

        try {
            $stmt = $db->prepare($sql);
            $stmt->execute($params);
            $products = $stmt->fetchAll();
        } catch (PDOException $e) {
            // Fallback: tabela stock_products jeszcze nie istnieje
            $sqlFallback = "
                SELECT
                    barcode,
                    MAX(product_name) AS product_name,
                    MAX(code_type) AS code_type,
                    unit,
                    COALESCE(SUM(CASE WHEN movement_type = 'in' THEN quantity ELSE 0 END), 0) AS total_in,
                    COALESCE(SUM(CASE WHEN movement_type = 'out' THEN quantity ELSE 0 END), 0) AS total_out,
                    COALESCE(SUM(CASE WHEN movement_type = 'in' THEN quantity ELSE 0 END), 0)
                    - COALESCE(SUM(CASE WHEN movement_type = 'out' THEN quantity ELSE 0 END), 0) AS current_stock,
                    MAX(created_at) AS last_movement,
                    NULL AS location_rack,
                    NULL AS location_shelf
                FROM stock_movements
            ";
            $fallbackParams = [];
            appendProductSearchCondition(
                $db,
                $sqlFallback,
                $fallbackParams,
                $search,
                'product_name',
                'barcode'
            );
            $sqlFallback .= " GROUP BY barcode, unit ORDER BY MAX(created_at) DESC";
            $stmt = $db->prepare($sqlFallback);
            $stmt->execute($fallbackParams);
            $products = $stmt->fetchAll();
        }

        $locationsMap = getLocationsMapForBarcodes($db, array_column($products, 'barcode'));
        foreach ($products as &$product) {
            $locations = $locationsMap[$product['barcode']] ?? [];
            $product['locations'] = $locations;
            $product['locations_count'] = count($locations);
            if (!empty($locations)) {
                $product['location_rack'] = $locations[0]['rack'];
                $product['location_shelf'] = $locations[0]['shelf'];
            }
        }
        unset($product);

        echo json_encode(['success' => true, 'products' => $products]);
        return;
    }

    if (empty($_GET['barcode'])) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'error' => 'Parametr barcode jest wymagany'
        ]);
        return;
    }

    $barcode = trim($_GET['barcode']);
    $barcode = resolveCanonicalBarcode($db, $barcode);

    // Pobierz podsumowanie stanów (po jednostkach) wraz z minimalnym stanem
    try {
        $stmt = $db->prepare("
            SELECT
                sm.unit,
                COALESCE(SUM(CASE WHEN sm.movement_type = 'in' THEN sm.quantity ELSE 0 END), 0) AS total_in,
                COALESCE(SUM(CASE WHEN sm.movement_type = 'out' THEN sm.quantity ELSE 0 END), 0) AS total_out,
                COALESCE(SUM(CASE WHEN sm.movement_type = 'in' THEN sm.quantity ELSE 0 END), 0)
                - COALESCE(SUM(CASE WHEN sm.movement_type = 'out' THEN sm.quantity ELSE 0 END), 0) AS current_stock,
                sps.min_quantity
            FROM stock_movements sm
            LEFT JOIN stock_product_settings sps
                   ON sps.barcode = sm.barcode AND sps.unit = sm.unit
            WHERE sm.barcode = ?
            GROUP BY sm.unit, sps.min_quantity
        ");
        $stmt->execute([$barcode]);
        $stockByUnit = $stmt->fetchAll();
    } catch (PDOException $e) {
        // Fallback bez tabeli stock_product_settings
        $stmt = $db->prepare("
            SELECT
                unit,
                COALESCE(SUM(CASE WHEN movement_type = 'in' THEN quantity ELSE 0 END), 0) AS total_in,
                COALESCE(SUM(CASE WHEN movement_type = 'out' THEN quantity ELSE 0 END), 0) AS total_out,
                COALESCE(SUM(CASE WHEN movement_type = 'in' THEN quantity ELSE 0 END), 0)
                - COALESCE(SUM(CASE WHEN movement_type = 'out' THEN quantity ELSE 0 END), 0) AS current_stock,
                NULL AS min_quantity
            FROM stock_movements
            WHERE barcode = ?
            GROUP BY unit
        ");
        $stmt->execute([$barcode]);
        $stockByUnit = $stmt->fetchAll();
    }

    $latest = getProductSnapshot($db, $barcode);

    // Pobierz ostatnie 20 ruchów
    try {
        $stmt = $db->prepare("
            SELECT id, movement_type, quantity, unit, note, user_name, issue_reason, vehicle_plate, issue_target, driver_name, created_at
            FROM stock_movements
            WHERE barcode = ?
            ORDER BY created_at DESC
            LIMIT 20
        ");
        $stmt->execute([$barcode]);
        $movements = $stmt->fetchAll();
    } catch (PDOException $e) {
        // Fallback: kolumny issue_target/driver_name jeszcze nie istnieją
        $stmt = $db->prepare("
            SELECT id, movement_type, quantity, unit, note, user_name, issue_reason, vehicle_plate, created_at
            FROM stock_movements
            WHERE barcode = ?
            ORDER BY created_at DESC
            LIMIT 20
        ");
        $stmt->execute([$barcode]);
        $movements = $stmt->fetchAll();
    }

    if ($latest) {
        $locations = getProductLocations($db, $barcode);
        $primary = !empty($locations) ? $locations[0] : null;

        echo json_encode([
            'success' => true,
            'exists' => true,
            'data' => [
                'barcode' => $barcode,
                'product_name' => $latest['product_name'],
                'code_type' => $latest['code_type'],
                'location_rack' => $primary['rack'] ?? null,
                'location_shelf' => $primary['shelf'] ?? null,
                'locations' => $locations,
                'locations_count' => count($locations),
            ],
            'stock' => $stockByUnit,
            'movements' => $movements,
        ]);
    } else {
        echo json_encode([
            'success' => true,
            'exists' => false,
            'data' => null,
            'stock' => [],
            'movements' => [],
        ]);
    }
}

/**
 * PUT - Zmiana nazwy produktu (aktualizacja product_name dla wszystkich ruchów z danym barcode)
 *
 * Body (JSON):
 *   {
 *     "barcode": "5901234123457",
 *     "new_name": "Nowa nazwa produktu"
 *   }
 */
function handlePut($db) {
    $input = json_decode(file_get_contents('php://input'), true);

    $action = isset($input['action']) ? trim($input['action']) : 'rename';

    if ($action === 'set_location') {
        handleSetLocation($db, $input);
        return;
    }

    if ($action === 'set_min_quantity') {
        handleSetMinQuantity($db, $input);
        return;
    }

    if ($action === 'change_barcode') {
        handleChangeBarcode($db, $input);
        return;
    }

    if (empty($input['barcode']) || empty($input['new_name'])) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'error' => 'Wymagane pola: barcode, new_name'
        ]);
        return;
    }

    $barcode = resolveCanonicalBarcode($db, trim($input['barcode']));
    $newName = trim($input['new_name']);
    $userId = isset($input['user_id']) ? (int)$input['user_id'] : null;
    $userName = isset($input['user_name']) ? trim($input['user_name']) : null;

    if (mb_strlen($newName) > 255) {
        $newName = mb_substr($newName, 0, 255);
    }

    $currentProduct = getProductSnapshot($db, $barcode);
    if (!$currentProduct) {
        http_response_code(404);
        echo json_encode([
            'success' => false,
            'error' => 'Produkt o podanym kodzie nie istnieje'
        ]);
        return;
    }

    $previousName = $currentProduct['product_name'] ?? null;

    try {
        $db->beginTransaction();

        $stmt = $db->prepare("UPDATE stock_movements SET product_name = ? WHERE barcode = ?");
        $stmt->execute([$newName, $barcode]);

        if (stockProductsTableExists($db)) {
            $stmt = $db->prepare("UPDATE stock_products SET product_name = ? WHERE barcode = ?");
            $stmt->execute([$newName, $barcode]);
        }

        insertProductChangeLog(
            $db,
            'rename',
            $barcode,
            $barcode,
            $barcode,
            $previousName,
            $newName,
            $userId,
            $userName
        );

        $db->commit();
    } catch (PDOException $e) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'error' => 'Błąd bazy danych: ' . $e->getMessage(),
        ]);
        return;
    }

    echo json_encode([
        'success' => true,
        'message' => 'Nazwa produktu została zmieniona',
        'data' => [
            'barcode' => $barcode,
            'product_name' => $newName,
            'code_type' => $currentProduct['code_type'] ?? detectCodeType($barcode),
        ]
    ]);
}

/**
 * PUT action=set_location — ustaw/wyczyść lokalizacje produktu.
 *
 * Body (JSON):
 *   {
 *     "action": "set_location",
 *     "barcode": "5901234123457",
 *     "locations": [
 *       {"rack": "A", "shelf": 0},
 *       {"rack": "A", "shelf": 1}
 *     ]
 *   }
 *
 * Wspierany jest też format legacy z pojedynczą parą
 * `location_rack` + `location_shelf`.
 */
function handleSetLocation($db, $input) {
    if (empty($input['barcode'])) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Wymagane pole: barcode']);
        return;
    }

    $barcode = resolveCanonicalBarcode($db, trim($input['barcode']));

    try {
        $locations = extractRequestedLocations($input);
    } catch (InvalidArgumentException $e) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => $e->getMessage()]);
        return;
    }

    // Upewnij się, że produkt istnieje (w stock_products lub stock_movements)
    if (!stockProductsTableExists($db)) {
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'error' => 'Tabela stock_products nie istnieje. Uruchom migrację (api/setup_database.sql sekcja 8/9).'
        ]);
        return;
    }

    $stmt = $db->prepare("SELECT 1 FROM stock_products WHERE barcode = ? LIMIT 1");
    $stmt->execute([$barcode]);
    $exists = (bool)$stmt->fetchColumn();

    if (!$exists) {
        // Spróbuj utworzyć wpis na podstawie ostatniego ruchu w stock_movements
        $base = getProductSnapshot($db, $barcode);
        if (!$base) {
            http_response_code(404);
            echo json_encode(['success' => false, 'error' => 'Produkt o podanym kodzie nie istnieje']);
            return;
        }
        $primary = !empty($locations) ? $locations[0] : null;
        upsertStockProduct(
            $db,
            $barcode,
            $base['code_type'],
            $base['product_name'],
            $base['unit'],
            $primary['rack'] ?? null,
            $primary['shelf'] ?? null
        );
    }

    try {
        saveProductLocations($db, $barcode, $locations);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'error' => $e->getMessage(),
        ]);
        return;
    }

    $primary = !empty($locations) ? $locations[0] : null;

    echo json_encode([
        'success' => true,
        'message' => 'Lokalizacja zaktualizowana',
        'data' => [
            'barcode' => $barcode,
            'location_rack' => $primary['rack'] ?? null,
            'location_shelf' => $primary['shelf'] ?? null,
            'locations' => $locations,
            'locations_count' => count($locations),
        ],
    ]);
}

/**
 * PUT action=set_min_quantity — ustaw lub usuń minimalny stan magazynowy.
 *
 * Body (JSON):
 *   {
 *     "action": "set_min_quantity",
 *     "barcode": "5901234123457",
 *     "unit": "szt",
 *     "min_quantity": 5,        // null lub 0 aby wyłączyć alert
 *     "user_id": 123             // opcjonalnie
 *   }
 */
function handleSetMinQuantity($db, $input) {
    if (empty($input['barcode'])) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Wymagane pole: barcode']);
        return;
    }

    $barcode = resolveCanonicalBarcode($db, trim($input['barcode']));
    $unit = isset($input['unit']) ? trim($input['unit']) : 'szt';
    $userId = isset($input['user_id']) ? (int)$input['user_id'] : null;

    $allowedUnits = ['szt', 'l', 'kg', 'm', 'opak', 'kpl'];
    if (!in_array($unit, $allowedUnits, true)) {
        $unit = 'szt';
    }

    $hasValue = array_key_exists('min_quantity', $input)
        && $input['min_quantity'] !== ''
        && $input['min_quantity'] !== null;

    try {
        if (!$hasValue) {
            // Usuń ustawienie
            $stmt = $db->prepare("DELETE FROM stock_product_settings WHERE barcode = ? AND unit = ?");
            $stmt->execute([$barcode, $unit]);
            echo json_encode([
                'success' => true,
                'message' => 'Minimalny stan usunięty',
                'data' => ['barcode' => $barcode, 'unit' => $unit, 'min_quantity' => null],
            ]);
            return;
        }

        $minQuantity = (float)$input['min_quantity'];
        if ($minQuantity < 0) {
            http_response_code(400);
            echo json_encode(['success' => false, 'error' => 'Minimalny stan nie może być ujemny']);
            return;
        }

        $stmt = $db->prepare("
            INSERT INTO stock_product_settings (barcode, unit, min_quantity, updated_at, updated_by)
            VALUES (?, ?, ?, NOW(), ?)
            ON DUPLICATE KEY UPDATE
                min_quantity = VALUES(min_quantity),
                updated_at = NOW(),
                updated_by = VALUES(updated_by)
        ");
        $stmt->execute([$barcode, $unit, $minQuantity, $userId]);

        echo json_encode([
            'success' => true,
            'message' => 'Minimalny stan zapisany',
            'data' => ['barcode' => $barcode, 'unit' => $unit, 'min_quantity' => $minQuantity],
        ]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'error' => 'Błąd bazy danych: ' . $e->getMessage(),
        ]);
    }
}

/**
 * PUT action=change_barcode — zmień kod produktu (wszędzie tam gdzie występuje).
 *
 * Body (JSON):
 *   {
 *     "action": "change_barcode",
 *     "barcode": "5901234123457",        // stary kod
 *     "new_barcode": "5901234999999",     // nowy kod (musi być wolny)
 *     "new_name": "Nowa nazwa produktu"   // opcjonalnie, w tej samej transakcji
 *   }
 *
 * Aktualizuje atomowo (transakcja) tabele:
 *   - stock_movements
 *   - stock_products
 *   - stock_product_settings (jeśli istnieje)
 */
function handleChangeBarcode($db, $input) {
    if (empty($input['barcode']) || empty($input['new_barcode'])) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Wymagane pola: barcode, new_barcode']);
        return;
    }

    $oldBarcode = resolveCanonicalBarcode($db, trim($input['barcode']));
    $newBarcode = trim($input['new_barcode']);
    $hasNewName = array_key_exists('new_name', $input);
    $newName = $hasNewName ? trim((string)$input['new_name']) : null;
    $userId = isset($input['user_id']) ? (int)$input['user_id'] : null;
    $userName = isset($input['user_name']) ? trim($input['user_name']) : null;

    if ($oldBarcode === $newBarcode) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Nowy kod jest taki sam jak stary']);
        return;
    }

    if (mb_strlen($newBarcode) < 1 || mb_strlen($newBarcode) > 128) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Nowy kod musi mieć od 1 do 128 znaków']);
        return;
    }

    if (!preg_match('/^[A-Za-z0-9._\-]+$/', $newBarcode)) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'error' => 'Nowy kod może zawierać tylko litery, cyfry oraz znaki . _ -'
        ]);
        return;
    }

    if ($hasNewName) {
        if ($newName === '') {
            http_response_code(400);
            echo json_encode(['success' => false, 'error' => 'Nowa nazwa produktu nie może być pusta']);
            return;
        }
        if (mb_strlen($newName) > 255) {
            $newName = mb_substr($newName, 0, 255);
        }
    }

    $currentProduct = getProductSnapshot($db, $oldBarcode);
    if (!$currentProduct) {
        http_response_code(404);
        echo json_encode(['success' => false, 'error' => 'Produkt o podanym kodzie nie istnieje']);
        return;
    }

    $previousName = $currentProduct['product_name'] ?? null;
    $updatedName = $hasNewName ? $newName : $previousName;
    $newCodeType = detectCodeType($newBarcode);

    if (resolveCanonicalBarcode($db, $newBarcode) !== $newBarcode) {
        http_response_code(409);
        echo json_encode([
            'success' => false,
            'error' => 'Nowy kod jest już zarezerwowany jako historyczny alias produktu'
        ]);
        return;
    }

    // Nowy kod musi być wolny — sprawdź w stock_movements i stock_products
    $stmt = $db->prepare("SELECT COUNT(*) FROM stock_movements WHERE barcode = ?");
    $stmt->execute([$newBarcode]);
    $existsInMov = (int)$stmt->fetchColumn() > 0;

    $existsInProd = false;
    if (stockProductsTableExists($db)) {
        $stmt = $db->prepare("SELECT COUNT(*) FROM stock_products WHERE barcode = ?");
        $stmt->execute([$newBarcode]);
        $existsInProd = (int)$stmt->fetchColumn() > 0;
    }

    if ($existsInMov || $existsInProd) {
        http_response_code(409);
        echo json_encode([
            'success' => false,
            'error' => 'Nowy kod jest już używany przez inny produkt'
        ]);
        return;
    }

    try {
        $db->beginTransaction();

        $stmt = $db->prepare("UPDATE stock_movements SET barcode = ?, code_type = ?, product_name = ? WHERE barcode = ?");
        $stmt->execute([$newBarcode, $newCodeType, $updatedName, $oldBarcode]);

        if (stockProductsTableExists($db)) {
            $stmt = $db->prepare("UPDATE stock_products SET barcode = ?, code_type = ?, product_name = ? WHERE barcode = ?");
            $stmt->execute([$newBarcode, $newCodeType, $updatedName, $oldBarcode]);
        }

        if (tableExists($db, 'stock_product_settings')) {
            $stmt = $db->prepare("UPDATE stock_product_settings SET barcode = ? WHERE barcode = ?");
            $stmt->execute([$newBarcode, $oldBarcode]);
        }

        if (stockProductLocationsTableExists($db)) {
            $stmt = $db->prepare("UPDATE stock_product_locations SET barcode = ? WHERE barcode = ?");
            $stmt->execute([$newBarcode, $oldBarcode]);
        }

        syncBarcodeAliasesAfterChange($db, $oldBarcode, $newBarcode);

        if ($updatedName !== $previousName) {
            insertProductChangeLog(
                $db,
                'rename',
                $newBarcode,
                $oldBarcode,
                $newBarcode,
                $previousName,
                $updatedName,
                $userId,
                $userName
            );
        }

        insertProductChangeLog(
            $db,
            'change_barcode',
            $newBarcode,
            $oldBarcode,
            $newBarcode,
            $previousName,
            $updatedName,
            $userId,
            $userName
        );

        $db->commit();

        echo json_encode([
            'success' => true,
            'message' => 'Kod produktu został zmieniony',
            'data' => [
                'old_barcode' => $oldBarcode,
                'barcode' => $newBarcode,
                'product_name' => $updatedName,
                'code_type' => $newCodeType,
            ],
        ]);
    } catch (PDOException $e) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'error' => 'Błąd bazy danych: ' . $e->getMessage(),
        ]);
    }
}
