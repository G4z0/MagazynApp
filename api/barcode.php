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

    // Lokalizacja (opcjonalnie — tylko przy ręcznym dodaniu nowego produktu).
    // Jeśli oba puste → NULL/NULL i pole w tabeli nie zostanie nadpisane.
    try {
        [$locationRack, $locationShelf] = normalizeLocation(
            $input['location_rack'] ?? null,
            $input['location_shelf'] ?? null
        );
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
        upsertStockProduct($db, $barcode, $codeType, $productName, $unit, $locationRack, $locationShelf);
    } catch (PDOException $e) {
        // Tabela stock_products jeszcze nie istnieje — nie blokuj zapisu ruchu.
        // (Wymagana migracja: api/setup_database.sql sekcja 8.)
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

        try {
            $stmt = $db->prepare("
                SELECT barcode, product_name, unit, location_rack, location_shelf
                FROM stock_products
                WHERE barcode = ?
                LIMIT 1
            ");
            $stmt->execute([$barcode]);
            $row = $stmt->fetch();
        } catch (PDOException $e) {
            // Tabela stock_products jeszcze nie istnieje
            echo json_encode(['success' => true, 'exists' => false, 'product' => null]);
            return;
        }

        if (!$row) {
            // Spróbuj fallback: produkt może być tylko w stock_movements (legacy, przed backfillem)
            $stmt = $db->prepare("
                SELECT barcode, product_name, unit
                FROM stock_movements
                WHERE barcode = ?
                ORDER BY created_at DESC
                LIMIT 1
            ");
            $stmt->execute([$barcode]);
            $row = $stmt->fetch();
            if (!$row) {
                echo json_encode(['success' => true, 'exists' => false, 'product' => null]);
                return;
            }
            $row['location_rack'] = null;
            $row['location_shelf'] = null;
        }

        echo json_encode([
            'success' => true,
            'exists' => true,
            'product' => [
                'barcode' => $row['barcode'],
                'product_name' => $row['product_name'],
                'unit' => $row['unit'],
                'location_rack' => $row['location_rack'],
                'location_shelf' => $row['location_shelf'] !== null ? (int)$row['location_shelf'] : null,
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

    // Alerty niskiego stanu (stan <= 0)
    if (isset($_GET['low_stock'])) {
        $stmt = $db->prepare("
            SELECT
                barcode,
                MAX(product_name) AS product_name,
                unit,
                COALESCE(SUM(CASE WHEN movement_type = 'in' THEN quantity ELSE 0 END), 0)
                - COALESCE(SUM(CASE WHEN movement_type = 'out' THEN quantity ELSE 0 END), 0) AS current_stock
            FROM stock_movements
            GROUP BY barcode, unit
            HAVING current_stock < 5
            ORDER BY current_stock ASC, MAX(product_name) ASC
            LIMIT 20
        ");
        $stmt->execute();
        $items = $stmt->fetchAll();

        echo json_encode(['success' => true, 'items' => $items]);
        return;
    }

    // Lista dostępnych części (stan > 0) — do wyboru w formularzu naprawy
    if (isset($_GET['parts'])) {
        $search = isset($_GET['search']) ? trim($_GET['search']) : '';

        $sql = "
            SELECT
                sm.barcode,
                MAX(sm.product_name) AS product_name,
                sm.unit,
                COALESCE(SUM(CASE WHEN sm.movement_type = 'in' THEN sm.quantity ELSE 0 END), 0)
                - COALESCE(SUM(CASE WHEN sm.movement_type = 'out' THEN sm.quantity ELSE 0 END), 0) AS current_stock,
                sp.location_rack,
                sp.location_shelf
            FROM stock_movements sm
            LEFT JOIN stock_products sp ON sp.barcode = sm.barcode
        ";
        $params = [];

        if ($search !== '') {
            $sql .= " WHERE (sm.product_name LIKE ? OR sm.barcode LIKE ?)";
            $params[] = "%$search%";
            $params[] = "%$search%";
        }

        $sql .= " GROUP BY sm.barcode, sm.unit, sp.location_rack, sp.location_shelf
                   HAVING current_stock > 0
                   ORDER BY MAX(sm.product_name) ASC";

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
            if ($search !== '') {
                $sqlFallback .= " WHERE (product_name LIKE ? OR barcode LIKE ?)";
            }
            $sqlFallback .= " GROUP BY barcode, unit
                               HAVING current_stock > 0
                               ORDER BY MAX(product_name) ASC";
            $stmt = $db->prepare($sqlFallback);
            $stmt->execute($params);
            $parts = $stmt->fetchAll();
        }

        echo json_encode(['success' => true, 'parts' => $parts]);
        return;
    }

    // Lista wszystkich produktów ze stanami
    if (isset($_GET['list'])) {
        $search = isset($_GET['search']) ? trim($_GET['search']) : '';

        $sql = "
            SELECT
                sm.barcode,
                MAX(sm.product_name) AS product_name,
                MAX(sm.code_type) AS code_type,
                sm.unit,
                COALESCE(SUM(CASE WHEN sm.movement_type = 'in' THEN sm.quantity ELSE 0 END), 0) AS total_in,
                COALESCE(SUM(CASE WHEN sm.movement_type = 'out' THEN sm.quantity ELSE 0 END), 0) AS total_out,
                COALESCE(SUM(CASE WHEN sm.movement_type = 'in' THEN sm.quantity ELSE 0 END), 0)
                - COALESCE(SUM(CASE WHEN sm.movement_type = 'out' THEN sm.quantity ELSE 0 END), 0) AS current_stock,
                MAX(sm.created_at) AS last_movement,
                sp.location_rack,
                sp.location_shelf
            FROM stock_movements sm
            LEFT JOIN stock_products sp ON sp.barcode = sm.barcode
        ";
        $params = [];

        if ($search !== '') {
            $sql .= " WHERE (sm.product_name LIKE ? OR sm.barcode LIKE ?)";
            $params[] = "%$search%";
            $params[] = "%$search%";
        }

        $sql .= " GROUP BY sm.barcode, sm.unit, sp.location_rack, sp.location_shelf ORDER BY MAX(sm.created_at) DESC";

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
            if ($search !== '') {
                $sqlFallback .= " WHERE (product_name LIKE ? OR barcode LIKE ?)";
            }
            $sqlFallback .= " GROUP BY barcode, unit ORDER BY MAX(created_at) DESC";
            $stmt = $db->prepare($sqlFallback);
            $stmt->execute($params);
            $products = $stmt->fetchAll();
        }

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

    // Pobierz podsumowanie stanów (po jednostkach)
    $stmt = $db->prepare("
        SELECT
            unit,
            COALESCE(SUM(CASE WHEN movement_type = 'in' THEN quantity ELSE 0 END), 0) AS total_in,
            COALESCE(SUM(CASE WHEN movement_type = 'out' THEN quantity ELSE 0 END), 0) AS total_out,
            COALESCE(SUM(CASE WHEN movement_type = 'in' THEN quantity ELSE 0 END), 0)
            - COALESCE(SUM(CASE WHEN movement_type = 'out' THEN quantity ELSE 0 END), 0) AS current_stock
        FROM stock_movements
        WHERE barcode = ?
        GROUP BY unit
    ");
    $stmt->execute([$barcode]);
    $stockByUnit = $stmt->fetchAll();

    // Pobierz ostatnią nazwę produktu i typ kodu
    $stmt = $db->prepare("
        SELECT product_name, code_type
        FROM stock_movements
        WHERE barcode = ?
        ORDER BY created_at DESC
        LIMIT 1
    ");
    $stmt->execute([$barcode]);
    $latest = $stmt->fetch();

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
        // Pobierz lokalizację jeśli istnieje wpis w stock_products
        $locationRack = null;
        $locationShelf = null;
        try {
            $stmt = $db->prepare("SELECT location_rack, location_shelf FROM stock_products WHERE barcode = ? LIMIT 1");
            $stmt->execute([$barcode]);
            $loc = $stmt->fetch();
            if ($loc) {
                $locationRack = $loc['location_rack'];
                $locationShelf = $loc['location_shelf'] !== null ? (int)$loc['location_shelf'] : null;
            }
        } catch (PDOException $e) {
            // Tabela jeszcze nie istnieje — zostawiamy null
        }

        echo json_encode([
            'success' => true,
            'exists' => true,
            'data' => [
                'barcode' => $barcode,
                'product_name' => $latest['product_name'],
                'code_type' => $latest['code_type'],
                'location_rack' => $locationRack,
                'location_shelf' => $locationShelf,
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

    if (empty($input['barcode']) || empty($input['new_name'])) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'error' => 'Wymagane pola: barcode, new_name'
        ]);
        return;
    }

    $barcode = trim($input['barcode']);
    $newName = trim($input['new_name']);

    if (mb_strlen($newName) > 255) {
        $newName = mb_substr($newName, 0, 255);
    }

    // Sprawdź czy produkt istnieje
    $stmt = $db->prepare("SELECT COUNT(*) AS cnt FROM stock_movements WHERE barcode = ?");
    $stmt->execute([$barcode]);
    $row = $stmt->fetch();

    if ((int)$row['cnt'] === 0) {
        http_response_code(404);
        echo json_encode([
            'success' => false,
            'error' => 'Produkt o podanym kodzie nie istnieje'
        ]);
        return;
    }

    // Zaktualizuj nazwę we wszystkich ruchach z tym kodem
    $stmt = $db->prepare("UPDATE stock_movements SET product_name = ? WHERE barcode = ?");
    $stmt->execute([$newName, $barcode]);

    // Zaktualizuj również słownik stock_products (jeśli tabela istnieje)
    try {
        $stmt = $db->prepare("UPDATE stock_products SET product_name = ? WHERE barcode = ?");
        $stmt->execute([$newName, $barcode]);
    } catch (PDOException $e) {
        // Tabela jeszcze nie istnieje — pomiń
    }

    echo json_encode([
        'success' => true,
        'message' => 'Nazwa produktu została zmieniona',
        'data' => [
            'barcode' => $barcode,
            'product_name' => $newName,
        ]
    ]);
}

/**
 * PUT action=set_location — ustaw/wyczyść lokalizację produktu.
 *
 * Body (JSON):
 *   {
 *     "action": "set_location",
 *     "barcode": "5901234123457",
 *     "location_rack": "A",       // lub null/"" aby wyczyścić
 *     "location_shelf": 0          // 0-99, lub null/"" aby wyczyścić
 *   }
 */
function handleSetLocation($db, $input) {
    if (empty($input['barcode'])) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Wymagane pole: barcode']);
        return;
    }

    $barcode = trim($input['barcode']);

    try {
        [$rack, $shelf] = normalizeLocation(
            $input['location_rack'] ?? null,
            $input['location_shelf'] ?? null
        );
    } catch (InvalidArgumentException $e) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => $e->getMessage()]);
        return;
    }

    // Upewnij się, że produkt istnieje (w stock_products lub stock_movements)
    try {
        $stmt = $db->prepare("SELECT 1 FROM stock_products WHERE barcode = ? LIMIT 1");
        $stmt->execute([$barcode]);
        $exists = (bool)$stmt->fetchColumn();
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'error' => 'Tabela stock_products nie istnieje. Uruchom migrację (api/setup_database.sql sekcja 8).'
        ]);
        return;
    }

    if (!$exists) {
        // Spróbuj utworzyć wpis na podstawie ostatniego ruchu w stock_movements
        $stmt = $db->prepare("
            SELECT product_name, code_type, unit
            FROM stock_movements
            WHERE barcode = ?
            ORDER BY created_at DESC
            LIMIT 1
        ");
        $stmt->execute([$barcode]);
        $base = $stmt->fetch();
        if (!$base) {
            http_response_code(404);
            echo json_encode(['success' => false, 'error' => 'Produkt o podanym kodzie nie istnieje']);
            return;
        }
        upsertStockProduct($db, $barcode, $base['code_type'], $base['product_name'], $base['unit'], $rack, $shelf);
    } else {
        $stmt = $db->prepare("
            UPDATE stock_products
            SET location_rack = ?, location_shelf = ?
            WHERE barcode = ?
        ");
        $stmt->execute([$rack, $shelf, $barcode]);
    }

    echo json_encode([
        'success' => true,
        'message' => 'Lokalizacja zaktualizowana',
        'data' => [
            'barcode' => $barcode,
            'location_rack' => $rack,
            'location_shelf' => $shelf,
        ],
    ]);
}
