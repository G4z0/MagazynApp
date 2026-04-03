<?php
/**
 * API endpoint do obsługi napraw z aplikacji MagazynApp.
 *
 * Endpointy:
 *   GET  /workshop.php?plate=XX12345  — Wyszukaj naczepę/pojazd po tablicy rejestracyjnej
 *   GET  /workshop.php?employees=1    — Pobierz listę pracowników
 *   GET  /workshop.php?services=1&type=2 — Pobierz listę usług dla typu obiektu
 *   POST /workshop.php                — Dodaj nową naprawę
 */

require_once __DIR__ . '/config.php';

$db = getDB();
$method = $_SERVER['REQUEST_METHOD'];

switch ($method) {
    case 'GET':
        handleGet($db);
        break;
    case 'POST':
        handlePost($db);
        break;
    default:
        http_response_code(405);
        echo json_encode(['success' => false, 'error' => 'Metoda niedozwolona']);
}

/**
 * GET — Wyszukaj naczepę/pojazd po tablicy lub pobierz listy słownikowe
 */
function handleGet($db) {
    // Lista pracowników (tylko warsztat — workplace_id = 3 = WORKSHOP)
    if (isset($_GET['employees'])) {
        $stmt = $db->prepare("
            SELECT id, firstname, lastname
            FROM employees
            WHERE deleted = 0 AND workplace_id = 3 AND date_of_dismissal IS NULL
            ORDER BY lastname, firstname
        ");
        $stmt->execute();
        $employees = $stmt->fetchAll();

        echo json_encode(['success' => true, 'employees' => $employees]);
        return;
    }

    // Lista usług warsztatowych dla danego typu (1=pojazd, 2=naczepa)
    if (isset($_GET['services'])) {
        $objectType = (int)($_GET['type'] ?? 2);
        if (!in_array($objectType, [1, 2], true)) {
            $objectType = 2;
        }

        // Pobierz grupy usług
        $stmt = $db->prepare("
            SELECT id, name, services, `order`
            FROM workshop_services_groups
            WHERE object_type = ?
            ORDER BY `order`
        ");
        $stmt->execute([$objectType]);
        $groups = $stmt->fetchAll();

        // Pobierz nazwy usług
        $stmt = $db->prepare("SELECT id, name FROM workshop_services_names ORDER BY name");
        $stmt->execute();
        $serviceNames = [];
        foreach ($stmt->fetchAll() as $row) {
            $serviceNames[(int)$row['id']] = $row['name'];
        }

        // Złącz grupy z nazwami
        $result = [];
        foreach ($groups as $group) {
            $serviceIds = json_decode($group['services'], true) ?: [];
            $items = [];
            foreach ($serviceIds as $sid) {
                $sid = (int)$sid;
                if (isset($serviceNames[$sid])) {
                    $items[] = ['id' => $sid, 'name' => $serviceNames[$sid]];
                }
            }
            $result[] = [
                'id' => (int)$group['id'],
                'name' => $group['name'],
                'services' => $items,
            ];
        }

        echo json_encode(['success' => true, 'groups' => $result]);
        return;
    }

    // Wyszukaj po tablicy rejestracyjnej
    if (empty($_GET['plate'])) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Parametr plate jest wymagany']);
        return;
    }

    $plate = trim(strtoupper(str_replace([' ', '-'], '', $_GET['plate'])));

    if (mb_strlen($plate) < 4) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Tablica za krótka (min 4 znaki)']);
        return;
    }

    $results = [];

    // Szukaj w naczepach
    $stmt = $db->prepare("
        SELECT id, plate, previous_plate, type, vin
        FROM semitrailers
        WHERE deleted = 0
          AND (REPLACE(REPLACE(plate, ' ', ''), '-', '') LIKE ? OR REPLACE(REPLACE(previous_plate, ' ', ''), '-', '') LIKE ?)
        LIMIT 5
    ");
    $like = '%' . $plate . '%';
    $stmt->execute([$like, $like]);
    foreach ($stmt->fetchAll() as $row) {
        $results[] = [
            'id' => (int)$row['id'],
            'plate' => $row['plate'],
            'previous_plate' => $row['previous_plate'],
            'vin' => $row['vin'],
            'object_type' => 2,
            'object_label' => 'Naczepa',
        ];
    }

    // Szukaj w pojazdach
    $stmt = $db->prepare("
        SELECT id, plate, previous_plate, model, vin
        FROM vehicles
        WHERE deleted = 0
          AND (REPLACE(REPLACE(plate, ' ', ''), '-', '') LIKE ? OR REPLACE(REPLACE(previous_plate, ' ', ''), '-', '') LIKE ?)
        LIMIT 5
    ");
    $stmt->execute([$like, $like]);
    foreach ($stmt->fetchAll() as $row) {
        $results[] = [
            'id' => (int)$row['id'],
            'plate' => $row['plate'],
            'previous_plate' => $row['previous_plate'],
            'model' => $row['model'] ?? null,
            'vin' => $row['vin'],
            'object_type' => 1,
            'object_label' => 'Pojazd' . ($row['model'] ? ' — ' . $row['model'] : ''),
        ];
    }

    if (empty($results)) {
        echo json_encode([
            'success' => true,
            'found' => false,
            'results' => [],
            'message' => 'Nie znaleziono pojazdu/naczepy o tablicy: ' . htmlspecialchars($plate, ENT_QUOTES, 'UTF-8'),
        ]);
        return;
    }

    echo json_encode([
        'success' => true,
        'found' => true,
        'results' => $results,
    ]);
}

/**
 * POST — Dodaj nową naprawę (workshop_services + opcjonalnie workshop_custom_services)
 */
function handlePost($db) {
    $input = json_decode(file_get_contents('php://input'), true);

    // Walidacja wymaganych pól
    $required = ['object_id', 'object_type', 'date', 'employee_id'];
    foreach ($required as $field) {
        if (empty($input[$field])) {
            http_response_code(400);
            echo json_encode(['success' => false, 'error' => "Pole '$field' jest wymagane"]);
            return;
        }
    }

    $objectId = (int)$input['object_id'];
    $objectType = (int)$input['object_type'];
    $date = $input['date']; // oczekiwany format: Y-m-d
    $employeeId = (int)$input['employee_id'];
    $mileage = (int)($input['mileage'] ?? 0);
    $laborCost = (float)($input['labor_cost'] ?? 0);
    $note = isset($input['note']) ? trim($input['note']) : '';
    $userId = (int)($input['user_id'] ?? 0);

    // Walidacja typu obiektu
    if (!in_array($objectType, [1, 2], true)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Typ obiektu musi być 1 (pojazd) lub 2 (naczepa)']);
        return;
    }

    // Walidacja daty
    $dateObj = DateTime::createFromFormat('Y-m-d', $date);
    if (!$dateObj || $dateObj->format('Y-m-d') !== $date) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Nieprawidłowy format daty (wymagany: Y-m-d)']);
        return;
    }

    // Sprawdź czy obiekt istnieje
    $table = $objectType === 1 ? 'vehicles' : 'semitrailers';
    $stmt = $db->prepare("SELECT id FROM `$table` WHERE id = ? AND deleted = 0");
    $stmt->execute([$objectId]);
    if (!$stmt->fetch()) {
        http_response_code(404);
        echo json_encode(['success' => false, 'error' => 'Nie znaleziono pojazdu/naczepy o podanym ID']);
        return;
    }

    // Sprawdź pracownika
    $stmt = $db->prepare("SELECT id FROM employees WHERE id = ? AND deleted = 0");
    $stmt->execute([$employeeId]);
    if (!$stmt->fetch()) {
        http_response_code(404);
        echo json_encode(['success' => false, 'error' => 'Nie znaleziono pracownika o podanym ID']);
        return;
    }

    // Ogranicz notatkę
    if (mb_strlen($note) > 2000) {
        $note = mb_substr($note, 0, 2000);
    }

    $now = date('Y-m-d H:i:s');

    try {
        $db->beginTransaction();

        // Wstaw główny rekord naprawy
        $stmt = $db->prepare("
            INSERT INTO workshop_services (object_id, type, date, mileage, creation_time, labor_cost, note, user_id, employee_repair_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ");
        $stmt->execute([$objectId, $objectType, $date, $mileage, $now, $laborCost, $note, $userId, $employeeId]);
        $serviceId = (int)$db->lastInsertId();

        // Wstaw usługi (predefined)
        $partsCost = 0;
        if (!empty($input['services']) && is_array($input['services'])) {
            $stmtSvc = $db->prepare("
                INSERT INTO workshop_repairs (service_id, service_name_id, note, amount)
                VALUES (?, ?, ?, ?)
            ");
            foreach ($input['services'] as $svc) {
                $svcId = (int)($svc['id'] ?? 0);
                $svcAmount = (float)($svc['amount'] ?? 0);
                $svcNote = trim($svc['note'] ?? '');
                if ($svcId > 0) {
                    $stmtSvc->execute([$serviceId, $svcId, $svcNote, $svcAmount]);
                    $partsCost += $svcAmount;
                }
            }
        }

        // Wstaw usługi custom
        if (!empty($input['custom_services']) && is_array($input['custom_services'])) {
            $stmtCustom = $db->prepare("
                INSERT INTO workshop_custom_services (service_id, service_name, note, amount)
                VALUES (?, ?, ?, ?)
            ");
            foreach ($input['custom_services'] as $cs) {
                $csName = trim($cs['name'] ?? '');
                $csAmount = (float)($cs['amount'] ?? 0);
                $csNote = trim($cs['note'] ?? '');
                if (mb_strlen($csName) > 0) {
                    $stmtCustom->execute([$serviceId, $csName, $csNote, $csAmount]);
                    $partsCost += $csAmount;
                }
            }
        }

        // Zaktualizuj koszty
        $totalCost = $laborCost + $partsCost;
        if ($totalCost > 0) {
            $stmt = $db->prepare("UPDATE workshop_services SET parts_cost = ?, total_cost = ? WHERE id = ?");
            $stmt->execute([$partsCost, $totalCost, $serviceId]);
        }

        $db->commit();

        http_response_code(201);
        echo json_encode([
            'success' => true,
            'message' => 'Naprawa została dodana',
            'data' => [
                'id' => $serviceId,
                'object_id' => $objectId,
                'object_type' => $objectType,
                'total_cost' => $totalCost,
            ],
        ]);
    } catch (Exception $e) {
        $db->rollBack();
        http_response_code(500);
        echo json_encode(['success' => false, 'error' => 'Błąd zapisu: ' . $e->getMessage()]);
    }
}
