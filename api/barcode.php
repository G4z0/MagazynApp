<?php
/**
 * API endpoint do obsługi ruchów magazynowych
 *
 * Endpointy:
 *   POST /barcode.php          - Zarejestruj ruch magazynowy (przyjęcie/wydanie)
 *   GET  /barcode.php?barcode=X - Pobierz stan magazynowy i historię ruchów
 */

require_once __DIR__ . '/config.php';

$db = getDB();
$method = $_SERVER['REQUEST_METHOD'];

switch ($method) {
    case 'POST':
        handlePost($db);
        break;
    case 'GET':
        handleGet($db);
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
 *     "note": "Mechanik Kowalski"     // opcjonalne
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

    // Ograniczenie długości notatki
    if ($note !== null && mb_strlen($note) > 255) {
        $note = mb_substr($note, 0, 255);
    }

    // Zapisz ruch magazynowy
    $stmt = $db->prepare("
        INSERT INTO stock_movements (barcode, code_type, product_name, movement_type, quantity, unit, note)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ");
    $stmt->execute([$barcode, $codeType, $productName, $movementType, $quantity, $unit, $note]);
    $newId = $db->lastInsertId();

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
 */
function handleGet($db) {
    // Lista dostępnych części (stan > 0) — do wyboru w formularzu naprawy
    if (isset($_GET['parts'])) {
        $search = isset($_GET['search']) ? trim($_GET['search']) : '';

        $sql = "
            SELECT
                barcode,
                MAX(product_name) AS product_name,
                unit,
                COALESCE(SUM(CASE WHEN movement_type = 'in' THEN quantity ELSE 0 END), 0)
                - COALESCE(SUM(CASE WHEN movement_type = 'out' THEN quantity ELSE 0 END), 0) AS current_stock
            FROM stock_movements
        ";
        $params = [];

        if ($search !== '') {
            $sql .= " WHERE (product_name LIKE ? OR barcode LIKE ?)";
            $params[] = "%$search%";
            $params[] = "%$search%";
        }

        $sql .= " GROUP BY barcode, unit
                   HAVING current_stock > 0
                   ORDER BY MAX(product_name) ASC";

        $stmt = $db->prepare($sql);
        $stmt->execute($params);
        $parts = $stmt->fetchAll();

        echo json_encode(['success' => true, 'parts' => $parts]);
        return;
    }

    // Lista wszystkich produktów ze stanami
    if (isset($_GET['list'])) {
        $search = isset($_GET['search']) ? trim($_GET['search']) : '';

        $sql = "
            SELECT
                barcode,
                MAX(product_name) AS product_name,
                MAX(code_type) AS code_type,
                unit,
                COALESCE(SUM(CASE WHEN movement_type = 'in' THEN quantity ELSE 0 END), 0) AS total_in,
                COALESCE(SUM(CASE WHEN movement_type = 'out' THEN quantity ELSE 0 END), 0) AS total_out,
                COALESCE(SUM(CASE WHEN movement_type = 'in' THEN quantity ELSE 0 END), 0)
                - COALESCE(SUM(CASE WHEN movement_type = 'out' THEN quantity ELSE 0 END), 0) AS current_stock,
                MAX(created_at) AS last_movement
            FROM stock_movements
        ";
        $params = [];

        if ($search !== '') {
            $sql .= " WHERE (product_name LIKE ? OR barcode LIKE ?)";
            $params[] = "%$search%";
            $params[] = "%$search%";
        }

        $sql .= " GROUP BY barcode, unit ORDER BY MAX(created_at) DESC";

        $stmt = $db->prepare($sql);
        $stmt->execute($params);
        $products = $stmt->fetchAll();

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
    $stmt = $db->prepare("
        SELECT id, movement_type, quantity, unit, note, created_at
        FROM stock_movements
        WHERE barcode = ?
        ORDER BY created_at DESC
        LIMIT 20
    ");
    $stmt->execute([$barcode]);
    $movements = $stmt->fetchAll();

    if ($latest) {
        echo json_encode([
            'success' => true,
            'exists' => true,
            'data' => [
                'barcode' => $barcode,
                'product_name' => $latest['product_name'],
                'code_type' => $latest['code_type'],
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
