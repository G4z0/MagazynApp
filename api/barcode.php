<?php
/**
 * API endpoint do obsługi kodów kreskowych
 *
 * Endpointy:
 *   POST /barcode.php          - Zapisz nowy kod kreskowy z nazwą produktu
 *   GET  /barcode.php?barcode=X - Sprawdź czy kod już istnieje w bazie
 *
 * Umieść ten plik w: htdocs/logisticserp/api/barcode.php
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
 * POST - Zapisz kod kreskowy + nazwę produktu
 *
 * Body (JSON):
 *   {
 *     "barcode": "5901234123457",
 *     "product_name": "Nazwa produktu"
 *   }
 */
function handlePost($db) {
    $input = json_decode(file_get_contents('php://input'), true);

    // Walidacja danych
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

    // Walidacja typu kodu
    if (!in_array($codeType, ['barcode', 'product_code'])) {
        $codeType = 'barcode';
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
    if (!in_array($unit, $allowedUnits)) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'error' => 'Niedozwolona jednostka. Dozwolone: ' . implode(', ', $allowedUnits)
        ]);
        return;
    }

    // Sprawdź czy kod już istnieje
    $stmt = $db->prepare("SELECT id, barcode, code_type, product_name, quantity, unit FROM scanned_products WHERE barcode = ?");
    $stmt->execute([$barcode]);
    $existing = $stmt->fetch();

    if ($existing) {
        // Aktualizuj istniejący wpis
        $stmt = $db->prepare("UPDATE scanned_products SET product_name = ?, quantity = ?, unit = ?, code_type = ? WHERE barcode = ?");
        $stmt->execute([$productName, $quantity, $unit, $codeType, $barcode]);

        echo json_encode([
            'success' => true,
            'message' => 'Produkt zaktualizowany',
            'data' => [
                'id' => $existing['id'],
                'barcode' => $barcode,
                'code_type' => $codeType,
                'product_name' => $productName,
                'quantity' => $quantity,
                'unit' => $unit,
            ]
        ]);
    } else {
        // Dodaj nowy wpis
        $stmt = $db->prepare("INSERT INTO scanned_products (barcode, code_type, product_name, quantity, unit) VALUES (?, ?, ?, ?, ?)");
        $stmt->execute([$barcode, $codeType, $productName, $quantity, $unit]);
        $newId = $db->lastInsertId();

        http_response_code(201);
        echo json_encode([
            'success' => true,
            'message' => 'Produkt dodany',
            'data' => [
                'id' => (int)$newId,
                'barcode' => $barcode,
                'code_type' => $codeType,
                'product_name' => $productName,
                'quantity' => $quantity,
                'unit' => $unit,
            ]
        ]);
    }
}

/**
 * GET - Sprawdź czy kod kreskowy istnieje w bazie
 *
 * Parametry URL:
 *   ?barcode=5901234123457
 */
function handleGet($db) {
    if (empty($_GET['barcode'])) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'error' => 'Parametr barcode jest wymagany'
        ]);
        return;
    }

    $barcode = trim($_GET['barcode']);

    $stmt = $db->prepare("SELECT id, barcode, code_type, product_name, quantity, unit, scanned_at FROM scanned_products WHERE barcode = ?");
    $stmt->execute([$barcode]);
    $product = $stmt->fetch();

    if ($product) {
        echo json_encode([
            'success' => true,
            'exists' => true,
            'data' => $product
        ]);
    } else {
        echo json_encode([
            'success' => true,
            'exists' => false,
            'data' => null
        ]);
    }
}
