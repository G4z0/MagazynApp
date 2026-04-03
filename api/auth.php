<?php
/**
 * API endpoint do autentykacji użytkowników MagazynApp
 *
 * POST /auth.php  — Logowanie (email + hasło)
 *
 * Uwierzytelnia względem tabeli `users` w bazie LogisticsERP.
 * Hasła weryfikowane przez password_verify() (bcrypt).
 */

require_once __DIR__ . '/config.php';

$db = getDB();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'error' => 'Metoda niedozwolona']);
    exit;
}

$input = json_decode(file_get_contents('php://input'), true);

if (empty($input['email']) || empty($input['password'])) {
    http_response_code(400);
    echo json_encode(['success' => false, 'error' => 'Email i hasło są wymagane']);
    exit;
}

$email = trim($input['email']);
$password = $input['password'];

// Walidacja formatu email
if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'error' => 'Nieprawidłowy format email']);
    exit;
}

// Pobierz użytkownika
$stmt = $db->prepare("
    SELECT id, email, password, first_name, last_name, blocked, deleted, login_attempts, last_login_attempt
    FROM users
    WHERE email = ?
    LIMIT 1
");
$stmt->execute([$email]);
$user = $stmt->fetch();

if (!$user) {
    http_response_code(401);
    echo json_encode(['success' => false, 'error' => 'Nieprawidłowy email lub hasło']);
    exit;
}

// Konto usunięte
if ((int)$user['deleted'] === 1) {
    http_response_code(401);
    echo json_encode(['success' => false, 'error' => 'Konto zostało usunięte']);
    exit;
}

// Konto zablokowane
if ((int)$user['blocked'] === 1) {
    http_response_code(401);
    echo json_encode(['success' => false, 'error' => 'Konto jest zablokowane']);
    exit;
}

// Limit prób logowania (5 prób, blokada 15 minut)
$maxAttempts = 5;
$lockoutMinutes = 15;
if ((int)$user['login_attempts'] >= $maxAttempts && $user['last_login_attempt']) {
    $lastAttempt = strtotime($user['last_login_attempt']);
    if (time() - $lastAttempt < $lockoutMinutes * 60) {
        http_response_code(429);
        echo json_encode(['success' => false, 'error' => 'Zbyt wiele prób logowania. Spróbuj za ' . $lockoutMinutes . ' minut.']);
        exit;
    }
    // Reset po upływie czasu blokady
    $stmt = $db->prepare("UPDATE users SET login_attempts = 0 WHERE id = ?");
    $stmt->execute([$user['id']]);
}

// Weryfikacja hasła (bcrypt)
if (!password_verify($password, $user['password'])) {
    // Zwiększ licznik prób
    $stmt = $db->prepare("UPDATE users SET login_attempts = login_attempts + 1, last_login_attempt = NOW() WHERE id = ?");
    $stmt->execute([$user['id']]);

    http_response_code(401);
    echo json_encode(['success' => false, 'error' => 'Nieprawidłowy email lub hasło']);
    exit;
}

// Logowanie udane — reset prób
$stmt = $db->prepare("UPDATE users SET login_attempts = 0, last_login = NOW() WHERE id = ?");
$stmt->execute([$user['id']]);

// Wygeneruj prosty token sesji
$token = bin2hex(random_bytes(32));

echo json_encode([
    'success' => true,
    'user' => [
        'id' => (int)$user['id'],
        'email' => $user['email'],
        'first_name' => $user['first_name'],
        'last_name' => $user['last_name'],
        'display_name' => trim($user['first_name'] . ' ' . $user['last_name']),
        'token' => $token,
    ],
]);
