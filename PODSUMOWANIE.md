# MagazynApp — Pełne podsumowanie aplikacji

**Wersja:** 1.2.1+4  
**Nazwa:** Warsztat - LogisticsERP  
**Technologie:** Flutter 3.41.1 (Dart 3.11.0) + PHP API (MySQL)  
**Serwer API:** 192.168.1.42  
**Baza danych:** logisticserp (MySQL, charset utf8mb4)

---

## 1. Architektura

```
┌─────────────────────────┐     HTTP (JSON)     ┌──────────────────────┐
│   Flutter App (Android)  │ ◄────────────────► │   PHP API (XAMPP)     │
│   - Material 3 Dark UI   │                    │   - auth.php          │
│   - SQLite (offline)     │                    │   - barcode.php       │
│   - Offline queue        │                    │   - workshop.php      │
└─────────────────────────┘                     └──────────┬───────────┘
                                                           │
                                                    ┌──────▼───────┐
                                                    │  MySQL DB     │
                                                    │  logisticserp │
                                                    └──────────────┘
```

---

## 2. Backend API (PHP)

### 2.1 `api/config.php` — Konfiguracja
- Połączenie PDO z MySQL (192.168.1.42, baza `logisticserp`)
- Ustawienia CORS (Access-Control-Allow-Origin: *)
- Charset utf8mb4
- Obsługa preflight OPTIONS

### 2.2 `api/auth.php` — Autentykacja
| Metoda | Opis |
|--------|------|
| `POST /auth.php` | Logowanie (email + hasło bcrypt) |

**Funkcje:**
- Walidacja formatu email
- Sprawdzanie konta (usunięte/zablokowane)
- Limit prób logowania: 5 prób / 15 min blokady
- Weryfikacja hasła bcrypt (`password_verify`)
- Generowanie tokena sesji (`bin2hex(random_bytes(32))`)
- Zwraca: id, email, first_name, last_name, display_name, token

### 2.3 `api/barcode.php` — Ruchy magazynowe
| Metoda | Endpoint | Opis |
|--------|----------|------|
| `POST` | `/barcode.php` | Zarejestruj ruch (przyjęcie/wydanie) |
| `GET` | `?barcode=X` | Stan i historia produktu |
| `GET` | `?list=1&search=` | Lista wszystkich produktów ze stanami |
| `GET` | `?parts=1&search=` | Dostępne części (stan > 0) |
| `GET` | `?low_stock=1` | Produkty z niskim stanem (< 5) |
| `GET` | `?next_sas=1` | Następny wolny kod SAS-N |
| `GET` | `?drivers=1&search=` | Lista kierowców (aktywni pracownicy) |
| `PUT` | `/barcode.php` | Zmiana nazwy produktu |

**POST — Ruch magazynowy:**
- Walidacja pól: barcode, product_name (wymagane)
- Typy ruchu: `in` (przyjęcie), `out` (wydanie)
- Jednostki: szt, l, kg, m, opak, kpl
- Kontrola stanu przy wydaniu (nie można wydać więcej niż jest)
- Pola dodatkowe: issue_reason (departure/replacement), vehicle_plate, issue_target (vehicle/driver), driver_id, driver_name
- Ograniczenia długości: notatka max 255, tablica max 20, kierowca max 100
- Fallback na starszą strukturę tabeli (bez issue_target/driver_id/driver_name)

### 2.4 `api/workshop.php` — Naprawy warsztatowe
| Metoda | Endpoint | Opis |
|--------|----------|------|
| `GET` | `?plate=XX12345` | Szukaj pojazdu/naczepy po tablicy |
| `GET` | `?employees=1` | Lista pracowników warsztatu |
| `GET` | `?services=1&type=2` | Lista usług warsztatowych (1=pojazd, 2=naczepa) |
| `POST` | `/workshop.php` | Dodaj nową naprawę |

**Szukanie po tablicy:**
- Szuka w tabelach `semitrailers` (naczepy) i `vehicles` (pojazdy)
- Normalizacja tablicy (usuwanie spacji i myślników)
- Wyniki: plate, previous_plate, vin, object_type (1/2), object_label

**Dodawanie naprawy:**
- Transakcja DB (begin/commit/rollback)
- Tabela: `workshop_services` (główny rekord)
- Tabela: `workshop_repairs` (usługi predefiniowane)
- Tabela: `workshop_custom_services` (usługi własne)
- Automatyczne kalkulowanie kosztów (labor_cost + parts_cost = total_cost)

### 2.5 Struktura bazy danych

**Tabela `stock_movements`:**
| Kolumna | Typ | Opis |
|---------|-----|------|
| id | INT AUTO_INCREMENT | PK |
| barcode | VARCHAR(128) | Kod kreskowy/produktowy |
| code_type | ENUM('barcode','product_code') | Typ kodu |
| product_name | VARCHAR(255) | Nazwa produktu |
| movement_type | ENUM('in','out') | Typ ruchu |
| quantity | DECIMAL(10,2) | Ilość |
| unit | VARCHAR(20) | Jednostka (szt/l/kg/m/opak/kpl) |
| note | VARCHAR(255) | Notatka |
| user_id | INT | ID użytkownika |
| user_name | VARCHAR(100) | Nazwa użytkownika |
| issue_reason | VARCHAR(50) | Powód wydania |
| vehicle_plate | VARCHAR(20) | Nr rejestracyjny |
| issue_target | VARCHAR(20) | Cel wydania (vehicle/driver) |
| driver_id | INT | ID kierowcy |
| driver_name | VARCHAR(100) | Imię kierowcy |
| delivery_id | INT | ID dostawy |
| created_at | DATETIME | Data utworzenia |

**Tabela `stock_deliveries`:**
- document_number, document_date, supplier, document_type, items_count, user_id

**Widok `stock_summary`:**
- Agregacja stanów magazynowych (total_in, total_out, current_stock) per barcode+unit

---

## 3. Aplikacja Flutter

### 3.1 Punkt wejścia (`main.dart`)
- Inicjalizacja tłumaczeń (`initTranslations()`)
- Start nasłuchiwania kolejki offline (`OfflineQueueService().startListening()`)
- Brama autoryzacji (`_AuthGate`) — sprawdza sesję → LoginScreen lub HomeScreen
- Motyw: Material 3 Dark z akcentem `#3498DB`

### 3.2 Ekrany (Screens)

#### `LoginScreen` — Ekran logowania
- Formularz: email + hasło
- Walidacja: email format, wymagane pola
- Obsługa błędów z API (wyświetlanie komunikatów)
- Po zalogowaniu → zapis do historii → HomeScreen

#### `HomeScreen` — Dashboard główny
- Nawigacja dolna: Główna, Stany, Skaner (centralny przycisk), Historia, Więcej
- Dashboard z kafelkami:
  - **Skanuj kod** → ScannerScreen
  - **Dodaj ręcznie** → ManualProductScreen
  - **Wydaj przedmiot** → BatchIssueScreen
  - **Dodaj naprawę** → PlateScannerScreen
  - **Stany magazynowe** → StockScreen
- Badge kolejki offline (licznik oczekujących)
- Powitanie użytkownika (imię z sesji)

#### `ScannerScreen` — Skaner kodów kreskowych
- Kamera z `mobile_scanner` (MobileScannerController)
- Regulowane okno skanowania (slider 40%-100%)
- Po wykryciu kodu → karta potwierdzenia (Zatwierdź/Odrzuć)
- Tryb `returnBarcodeOnly` — zwraca kod bez otwierania formularza
- Przyciski: OCR (→ OcrCaptureScreen), Ręcznie (dialog wpisywania kodu)
- Latarka, przełączanie kamery
- Wskaźnik kolejki offline

#### `ProductFormScreen` — Formularz ruchu magazynowego
- Przełącznik: Przyjęcie (in) / Wydanie (out)
- Pola: nazwa produktu, ilość, jednostka (6 opcji z ikonami)
- Przeliczanie opakowań/kompletów na jednostki bazowe
- Przy wydaniu:
  - Powód: wyjazd z bazy / na zamianę
  - Cel: samochód (nr rejestracyjny) / kierowca (wyszukiwarka) / warsztat
  - Kontrola stanu magazynowego (max ilość)
- Podgląd aktualnego stanu i ostatnich ruchów
- Auto-detekcja typu kodu (barcode vs product_code)
- Fallback offline → kolejka + dialog informacyjny
- Zapis do lokalnej historii

#### `ManualProductScreen` — Ręczne dodawanie produktu
- Auto-generowanie kodu wewnętrznego (SAS-N) z API
- Formularz: nazwa, ilość, jednostka, notatka
- Zawsze ruch typu "przyjęcie" (in)
- Typ kodu: product_code
- Fallback offline → kolejka

#### `BatchIssueScreen` — Wsadowe wydawanie produktów
- Lista pozycji do wydania (skan / ręcznie / z listy magazynu)
- Wspólne ustawienia: powód, cel (samochód/kierowca)
- Deduplikacja — zwiększanie ilości zamiast duplikatów
- Wydanie wszystkich pozycji jednym przyciskiem
- Raport: sukces/częściowy sukces z liczbą wydanych
- Fallback offline dla każdej pozycji

#### `StockScreen` — Stany magazynowe
- Lista produktów z aktualnym stanem
- Wyszukiwarka z debounce (400ms)
- Karta produktu: nazwa, kod, stan, total_in/total_out, data ostatniego ruchu
- Oznaczenie niskiego stanu (czerwona ramka, ikona ostrzeżenia)
- Szczegóły produktu (bottom sheet):
  - Historia ruchów
  - Przycisk "Wydaj towar"
  - Przycisk "Zmień nazwę"
- Pull-to-refresh

#### `PlateScannerScreen` — Skaner tablic rejestracyjnych
- Kamera z `camera` plugin + OCR (`google_mlkit_text_recognition`)
- Przycinanie zdjęcia do strefy tablicy (środkowy pas 85%×25%)
- Regex rozpoznawania polskich tablic: `^[A-Z]{1,3}\s?[A-Z0-9]{2,5}$`
- Przy wielu kandydatach → bottom sheet z wyborem
- Po rozpoznaniu → szukanie w bazie (API workshop) → formularz naprawy
- Opcja ręcznego wpisania tablicy

#### `RepairFormScreen` — Formularz naprawy
- Dane pojazdu/naczepy (tablica, typ, VIN)
- Pola: data, pracownik (dropdown), przebieg, koszt robocizny
- Usługi warsztatowe (grupy rozwijane z checkboxami, kwota + notatka)
- Usługi własne (dynamiczna lista: nazwa, kwota, notatka)
- Wykorzystane części (wybór z dostępnych w magazynie)
- Notatka opisowa
- Zapis do historii lokalnej

#### `OcrCaptureScreen` — Rozpoznawanie tekstu (OCR)
- Kamera z regulowanym celownikiem
- Przycinanie zdjęcia do obszaru celownika
- Rozpoznawanie tekstu → lista wyników
- Możliwość edycji rozpoznanego tekstu
- Wybór kodu → przejście do ProductFormScreen

#### `HistoryScreen` — Historia działań
- Lista lokalnych działań (SQLite)
- Typy: stock_in, stock_out, scan, login, logout, repair_add
- Formatowanie dat (Dzisiaj, Wczoraj, dd.MM.yyyy)
- Czyszczenie historii (z potwierdzeniem)
- Pull-to-refresh

#### `SettingsScreen` — Ustawienia / Więcej
- Informacje o użytkowniku (imię, email)
- O aplikacji (dialog z opisem funkcji)
- Sprawdzanie połączenia z serwerem (ping + status)
- Kolejka offline (podgląd, wymuszenie synchronizacji)
- Zmiana języka (5 języków)
- Wylogowanie (z potwierdzeniem)

### 3.3 Serwisy (Services)

#### `ApiService` — Komunikacja z API magazynowym
| Metoda | Opis |
|--------|------|
| `saveProduct()` | Rejestracja ruchu (POST) |
| `checkBarcode()` | Pobranie stanu i historii (GET ?barcode=) |
| `getStockList()` | Lista produktów ze stanami (GET ?list=1) |
| `getAvailableParts()` | Dostępne części (GET ?parts=1) |
| `getLowStockAlerts()` | Alerty niskiego stanu (GET ?low_stock=1) |
| `getNextSasCode()` | Następny kod SAS-N (GET ?next_sas=1) |
| `getDrivers()` | Lista kierowców (GET ?drivers=1) |
| `renameProduct()` | Zmiana nazwy (PUT) |

- Timeout: 10 sekund
- Wyjątki: `ApiException` (błąd biznesowy), `NetworkException` (brak sieci)
- Auto-dołączanie user_id i user_name z AuthService

#### `AuthService` — Autentykacja (Singleton)
| Metoda | Opis |
|--------|------|
| `loadSession()` | Ładowanie sesji z SharedPreferences |
| `login()` | Logowanie przez API |
| `logout()` | Czyszczenie sesji |

- Przechowywanie: userId, email, displayName, token w SharedPreferences
- Właściwość `isLoggedIn` → sprawdza userId + token

#### `OfflineQueueService` — Kolejka offline (Singleton)
| Metoda | Opis |
|--------|------|
| `startListening()` | Nasłuchiwanie zmian sieci (connectivity_plus) |
| `enqueue()` | Dodanie ruchu do lokalnej kolejki (SQLite) |
| `syncQueue()` | Wysłanie kolejki na serwer |
| `getAll()` | Pobranie wszystkich oczekujących |

- SQLite baza: `offline_queue.db` (wersja 6, z migracjami)
- Auto-sync po wykryciu połączenia WiFi
- `pendingCount` — ValueNotifier<int> do wyświetlania badge'a w UI
- Błędy biznesowe (ApiException) → usuwane z kolejki (nie ponawiaj)
- Błędy sieciowe → zostaw i ponów później

#### `LocalHistoryService` — Historia lokalna (Singleton)
| Metoda | Opis |
|--------|------|
| `add()` | Dodanie wpisu historii |
| `getHistory()` | Pobranie historii (limit) |
| `clear()` | Wyczyszczenie historii |
| `count()` | Liczba wpisów |

- SQLite baza: `local_history.db` (wersja 1)
- Pola: action_type, title, subtitle, barcode, quantity, unit, user_name, created_at

#### `WorkshopApiService` — Komunikacja z API warsztatu
| Metoda | Opis |
|--------|------|
| `searchByPlate()` | Szukaj pojazdu po tablicy |
| `getEmployees()` | Lista pracowników warsztatu |
| `getServiceGroups()` | Grupy usług warsztatowych |
| `addRepair()` | Dodanie nowej naprawy |

### 3.4 Model danych

#### `CodeType` (enum)
- `barcode` — kod kreskowy (EAN/UPC, 8-13 cyfr)
- `productCode` — kod produktu (litery, kropki, myślniki)
- Auto-detekcja na podstawie zawartości (`detect()`)

### 3.5 Wielojęzyczność (i18n)
- System tłumaczeń: `tr('KEY', args: {'count': '5'})`
- 5 języków: 🇵🇱 Polski, 🇬🇧 English, 🇺🇦 Українська, 🇷🇺 Русский, 🇬🇪 ქართული
- Przechowywanie wyboru w SharedPreferences
- ~170 kluczy tłumaczeń

---

## 4. Zależności (Flutter)

| Pakiet | Wersja | Cel |
|--------|--------|-----|
| mobile_scanner | ^5.1.1 | Skanowanie kodów kreskowych (kamera) |
| http | ^1.2.1 | Zapytania HTTP do API |
| sqflite | ^2.3.0 | Lokalna baza SQLite (kolejka offline + historia) |
| path | ^1.9.0 | Ścieżki plików |
| connectivity_plus | ^6.0.3 | Monitoring połączenia sieciowego |
| google_mlkit_text_recognition | ^0.14.0 | OCR — rozpoznawanie tekstu |
| camera | ^0.11.1 | Dostęp do kamery (OCR/tablica) |
| shared_preferences | ^2.2.2 | Przechowywanie sesji/preferencji |
| cupertino_icons | ^1.0.6 | Ikony |

---

## 5. Funkcje — podsumowanie

| # | Funkcja | Status |
|---|---------|--------|
| 1 | Logowanie kontem ERP (email + hasło bcrypt) | ✅ |
| 2 | Skanowanie kodów kreskowych (kamera) | ✅ |
| 3 | OCR — rozpoznawanie kodów produktów z etykiet | ✅ |
| 4 | Przyjęcie towaru (in) z walidacją | ✅ |
| 5 | Wydanie towaru (out) z kontrolą stanu | ✅ |
| 6 | Wydanie wsadowe (wiele pozycji naraz) | ✅ |
| 7 | Przeliczanie opakowań/kompletów na jednostki bazowe | ✅ |
| 8 | Ręczne dodawanie produktu z auto-kodem (SAS-N) | ✅ |
| 9 | Przeglądanie stanów magazynowych z wyszukiwaniem | ✅ |
| 10 | Historia ruchów per produkt | ✅ |
| 11 | Zmiana nazwy produktu | ✅ |
| 12 | Alerty niskiego stanu (< 5) | ✅ |
| 13 | Skanowanie tablic rejestracyjnych (OCR) | ✅ |
| 14 | Wyszukiwanie pojazdów/naczep w bazie | ✅ |
| 15 | Dodawanie napraw (usługi + custom + koszty) | ✅ |
| 16 | Wybór pracownika warsztatu | ✅ |
| 17 | Wybór kierowcy / samochodu przy wydaniu | ✅ |
| 18 | Tryb offline z automatyczną synchronizacją | ✅ |
| 19 | Kolejka offline z badge'em w UI | ✅ |
| 20 | Historia działań na urządzeniu (lokalna) | ✅ |
| 21 | Wielojęzyczność (5 języków) | ✅ |
| 22 | Sprawdzanie połączenia z serwerem | ✅ |
| 23 | Wylogowanie z czyszczeniem sesji | ✅ |
| 24 | Ciemny motyw Material 3 | ✅ |

---

## 6. Struktura plików

```
MagazynApp/
├── api/                              # Backend PHP
│   ├── config.php                    # Konfiguracja DB + CORS
│   ├── auth.php                      # Logowanie (POST)
│   ├── barcode.php                   # Ruchy magazynowe (GET/POST/PUT)
│   ├── workshop.php                  # Naprawy (GET/POST)
│   └── setup_database.sql            # Schemat bazy danych
│
├── flutter_app/                      # Aplikacja mobilna
│   ├── pubspec.yaml                  # Zależności (v1.2.1+4)
│   ├── lib/
│   │   ├── main.dart                 # Punkt wejścia + AuthGate
│   │   ├── l10n/
│   │   │   └── translations.dart     # System tłumaczeń (5 języków)
│   │   ├── models/
│   │   │   └── code_type.dart        # Enum CodeType (barcode/product_code)
│   │   ├── screens/
│   │   │   ├── home_screen.dart      # Dashboard + nawigacja
│   │   │   ├── login_screen.dart     # Logowanie
│   │   │   ├── scanner_screen.dart   # Skaner kodów kreskowych
│   │   │   ├── product_form_screen.dart  # Formularz przyjęcia/wydania
│   │   │   ├── manual_product_screen.dart # Ręczne dodawanie (SAS-N)
│   │   │   ├── batch_issue_screen.dart    # Wydanie wsadowe
│   │   │   ├── stock_screen.dart     # Stany magazynowe
│   │   │   ├── plate_scanner_screen.dart  # Skaner tablic (OCR)
│   │   │   ├── repair_form_screen.dart    # Formularz naprawy
│   │   │   ├── ocr_capture_screen.dart    # OCR kodów produktów
│   │   │   ├── history_screen.dart   # Historia działań
│   │   │   └── settings_screen.dart  # Ustawienia / Więcej
│   │   └── services/
│   │       ├── api_service.dart      # API magazynowe
│   │       ├── auth_service.dart     # Autentykacja
│   │       ├── offline_queue_service.dart  # Kolejka offline
│   │       ├── local_history_service.dart  # Historia lokalna
│   │       └── workshop_api_service.dart   # API warsztatu
│   └── assets/
│       └── logo.png                  # Logo aplikacji
│
├── INSTRUKCJA.md
└── README.md
```

---

## 7. Przepływ danych — przykłady

### Przyjęcie towaru (online):
```
Skaner → kod → ProductFormScreen → ApiService.saveProduct() → POST barcode.php → MySQL
                                 → LocalHistoryService.add()
```

### Wydanie towaru (offline):
```
Skaner → kod → ProductFormScreen → NetworkException
                                 → OfflineQueueService.enqueue() → SQLite (queue)
                                 → [WiFi wróci] → syncQueue() → POST barcode.php → MySQL
```

### Naprawa:
```
PlateScannerScreen → OCR tablica → WorkshopApiService.searchByPlate() → GET workshop.php
                   → RepairFormScreen → WorkshopApiService.addRepair() → POST workshop.php → MySQL
```
