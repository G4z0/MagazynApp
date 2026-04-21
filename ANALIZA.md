# MagazynApp — Analiza możliwych ulepszeń

> Data analizy: 21.04.2026 · Wersja aplikacji: **1.2.1+4**
> Zakres: backend PHP (`api/`) + Flutter (`flutter_app/lib/`) + schemat DB.
>
> Każdy punkt zawiera: **co**, **dlaczego boli**, **propozycję**, **szacunek wagi**
> (🔴 krytyczne / 🟠 ważne / 🟡 nice-to-have) i **wpływ na zgodność wsteczną**.
>
> **Model wdrożenia (ustalone 21.04.2026):** API i aplikacja działają **wyłącznie w sieci LAN**
> (192.168.1.42). Dostęp zdalny tylko przez VPN do tej sieci — nigdy bez. Punkty
> bezpieczeństwa, które zakładają wystawienie API do internetu (CORS publiczny,
> rate-limit per IP, HTTPS), są zachowane jako kontekst, ale obniżono ich priorytet.
> Realne ryzyko ogranicza się do *insider threat* w LAN/VPN.

---

## 1. Bezpieczeństwo i autoryzacja

### 1.1 � Token sesji nigdzie nie jest weryfikowany przez API
**Plik:** [api/barcode.php](api/barcode.php), [api/workshop.php](api/workshop.php), [api/config.php](api/config.php)

`auth.php` generuje `bin2hex(random_bytes(32))`, ale token nie jest **nigdzie zapisywany** w bazie ani sprawdzany przy kolejnych requestach. Każdy w LAN/VPN może uderzyć w `barcode.php` z dowolnym `user_id`/`user_name` w body i zarejestrować ruch jako kto chce. W modelu LAN-only nie jest to atak z zewnątrz, ale audyt historii ruchów pozostaje niewiarygodny — nie da się rozróżnić pomyłki operatora od podszycia (nawet nieumyślnego, np. ten sam endpoint wywołany przez skrypt testowy).

**Propozycja:**
- Tabela `app_sessions (token CHAR(64) PK, user_id INT, created_at, last_used_at, expires_at)`.
- `auth.php` zapisuje token + TTL (np. 30 dni rolling).
- Wspólny `require_auth($db)` w `config.php` — czyta `Authorization: Bearer …`, weryfikuje, zwraca `$user`. Wszystkie endpointy używają tego zamiast `user_id` z body.
- Flutter: `ApiService` dodaje header `Authorization: Bearer ${AuthService().token}`.

**Wstecznie:** wymaga release Fluttera + migracji DB; userzy z v1.2.1 dostaną 401 → ekran logowania (akceptowalne).

---

### 1.2 � Hasło DB w repo
**Plik:** [api/config.php](api/config.php#L10)

`DB_PASS` zaszyte w pliku, który jest w gicie. Przy LAN-only ryzyko ograniczone, ale każdy klon repo na laptopa pracownika to potencjalny wyciek poświadczeń produkcyjnej bazy.

**Propozycja:** `config.php` ładuje z `config.local.php` (gitignored) lub `getenv('DB_PASS')`. Commit `config.example.php` z placeholderami. Dodać `.gitignore` na `config.php`.

---

### 1.3 � Token w `SharedPreferences` (plaintext)
**Plik:** [flutter_app/lib/services/auth_service.dart](flutter_app/lib/services/auth_service.dart)

Świadomy kompromis wg `CLAUDE.md`. W modelu LAN-only ryzyko jest niskie (urządzenie zgubione/skradzione + ktoś w sieci firmowej/VPN). Po wprowadzeniu pkt 1.1 wartość tokena rośnie — wtedy migracja do `flutter_secure_storage` ma sens.

**Propozycja:** osobny ticket. Zachować odczyt z `SharedPreferences` jako fallback przez 1 release dla migracji istniejących sesji, potem usunąć.

---

### 1.4 � CORS `*` + brak rate-limitu poza loginem — **nieistotne w LAN-only**
**Plik:** [api/config.php](api/config.php#L37)

W modelu LAN/VPN to **nieistotne**. CORS dotyczy tylko klientów przeglądarkowych z innym originem — apka mobilna ignoruje. Rate-limit per IP w sieci kilkunastu urządzeń to overkill.

**Co warto mimo to:** komentarz w `config.php` że `CORS *` jest świadomą decyzją dla LAN — żeby nikt przy okazji nie wystawił tego na zewnątrz bez przemyślenia.

---

### 1.5 🟡 `htmlspecialchars` w komunikacie JSON
**Plik:** [api/workshop.php](api/workshop.php#L150)

`'message' => '… ' . htmlspecialchars($plate, …)` — to pole JSON konsumowane przez Fluttera, nie HTML. Encoded entities (`&amp;`) wyświetlą się userowi jako tekst. Usunąć escape, ewentualnie sanityzować przez whitelistę znaków.

---

### 1.6 🟡 Brak walidacji hasła przy logowaniu po stronie aplikacji
**Plik:** [flutter_app/lib/screens/login_screen.dart](flutter_app/lib/screens/login_screen.dart)

Walidacja jest tylko po stronie API. Można dodać minimum 1 znak przed wysłaniem — drobiazg, ale oszczędza request.

---

## 2. Architektura kodu Flutter

### 2.1 🟠 `ApiService` ma metody **statyczne** + zależność od `AuthService` (singleton)
**Plik:** [flutter_app/lib/services/api_service.dart](flutter_app/lib/services/api_service.dart#L67)

Mieszanka: `ApiService` to klasa ze statykami, `AuthService` to singleton. Kolejka offline woła `ApiService.saveProduct`, ale w docelowej wersji z tokenem (pkt 1.1) trzeba trzymać też `AuthService` aktualny w tle. Brak abstrakcji utrudni dodanie testów i interceptora 401 → wylogowanie.

**Propozycja:** zamienić `ApiService` na singleton (`ApiService()`), dodać prywatną metodę `_request()` z:
- automatycznym dorzucaniem `Authorization`,
- jednolitą obsługą 401 → `AuthService().logout()` + nawigacja na login,
- jednolitą obsługą 5xx/timeout → `NetworkException`,
- jednolitym dekodowaniem JSON i sprawdzeniem `success`.

To usunie ~100 linii powtórzeń w `ApiService`/`WorkshopApiService` (każda metoda ma własny `try/catch + jsonDecode + statusCode check`).

---

### 2.2 🟠 Bezpieczne `catch (_)` połykające błędy
**Plik:** [flutter_app/lib/services/api_service.dart](flutter_app/lib/services/api_service.dart#L114) i kilka kolejnych metod

`getStockList`, `checkBarcode`, `getAvailableParts`, `getLowStockAlerts`, `getNextSasCode` mają `catch (_) { return []; }` — to sprzeczne z zasadą z `CLAUDE.md` ("nigdy gołego `Exception`"). Ekran nie wie, czy lista jest pusta bo brak produktów, brak sieci, czy 500. UX: user widzi "brak produktów" mimo że rzeczywistość to brak WiFi.

**Propozycja:** rzucać `NetworkException`/`ApiException` jak w `saveProduct`. Ekrany rozróżniają stan: empty / error / offline.

---

### 2.3 🟠 `URL` zaszyty w 3 miejscach
`http://192.168.1.42` jest w `auth_service.dart`, `api_service.dart`, `workshop_api_service.dart`. Każda zmiana adresu = grep + 3 edycje + ryzyko ominięcia.

**Propozycja:** `lib/config/api_config.dart` z `static const baseUrl` oraz przyszłym builderem dla `Authorization`. Albo `--dart-define=API_HOST=...` przy build (ułatwia stage/prod).

---

### 2.4 🟡 `restartApp` przez `findAncestorStateOfType`
**Plik:** [flutter_app/lib/main.dart](flutter_app/lib/main.dart#L26)

Działa, ale rebuild całego drzewa po zmianie języka traci stan ekranów (np. wpisany formularz). Dla i18n wystarczy `ValueListenableBuilder<Locale>` na `MaterialApp.locale`. Zmiana niepilna, ale upraszcza.

---

### 2.5 🟡 Przyszłe zmiany schematu kolejki
**Plik:** [flutter_app/lib/services/offline_queue_service.dart](flutter_app/lib/services/offline_queue_service.dart)

Tabela `queue` ma 14 kolumn typu `barcode/driver_id/...`. Każdy nowy typ zlecenia (np. naprawa offline) = ALTER + bump wersji. Skala migracji już jest 6.

**Propozycja:** generyczna tabela `queue (id, action TEXT, payload TEXT JSON, created_at, attempts INT, last_error TEXT)`. `enqueue` serializuje typowane DTO do JSON. Łatwo dodać kolejne akcje (np. `add_repair`, `rename_product`) bez ALTER. Jednorazowa migracja v6→v7 przepisuje istniejące wiersze do `payload`.

**Wstecznie:** trzeba przepisać dane w `onUpgrade`. Po release nie ma już kolumn typowanych.

---

### 2.6 🟡 `attempts` i `last_error` w kolejce
Obecnie błąd sieci = retry w nieskończoność (przy każdym `onConnectivityChanged`). Brak limitów = ryzyko zapętlenia, jeśli serwer odpowiada 502 z błędem traktowanym jako "sieciowy".

**Propozycja:** w nowej tabeli (pkt 2.5) trzymać `attempts` i `last_error`. Po np. 10 nieudanych próbach przerzucać do "dead letter" — UI w `SettingsScreen` pokazuje user'owi wpisy do ręcznej akceptacji/usunięcia.

---

### 2.7 🟡 `connectivity_plus` ≠ realna sieć
Aktualny listener leci `syncQueue()` przy każdym `onConnectivityChanged` z connection != none. Na Androidzie często zdarza się false-positive (WiFi bez dostępu, captive portal).

**Propozycja:** krótki ping `auth.php` (HEAD/200) przed `syncQueue`. Albo wbudowany `InternetConnectionChecker` z osobnego pakietu (uwaga: pkt 1 z `CLAUDE.md` — pytamy o nowe deps).

---

## 3. Backend PHP

### 3.1 🟠 Brak `created_at` (klient) — tylko `created_at` (serwer)
**Plik:** [api/setup_database.sql](api/setup_database.sql#L26)

`stock_movements.created_at` to `DEFAULT CURRENT_TIMESTAMP` — ustawiany w momencie INSERT, nie wtedy gdy operator zeskanował. Dla wpisów z kolejki offline (zsynchronizowanych po godzinach) historia jest fałszywa.

**Propozycja:** dodać `client_created_at DATETIME NULL`, Flutter wysyła ten timestamp z `enqueue`. Raporty używają `COALESCE(client_created_at, created_at)`.

---

### 3.2 🟠 `stock_summary` z `MAX(product_name)` w `GROUP BY barcode, unit`
**Plik:** [api/setup_database.sql](api/setup_database.sql#L42), [api/barcode.php](api/barcode.php) — kilka miejsc

Po zmianie nazwy (`renameProduct`) historia ma wiele różnych `product_name` per `barcode`. `MAX(product_name)` to lottery (alfabetycznie). Co więcej, brak osobnej tabeli "produktów" oznacza, że nazwa jest **zdenormalizowana** w każdym ruchu — `renameProduct` musi UPDATE'ować wszystkie ruchy. Audytowo również słabe (utrata historii starej nazwy).

**Propozycja:** osobna tabela `stock_products (barcode PK, product_name, unit, created_at, updated_at)`. `stock_movements` referuje tylko `barcode`. To rozwiąże:
- niski stan ostrzeżenia (`< 5`) — można dodać per-produkt `min_stock`,
- alias produktu (np. SAS-N + EAN dla tego samego produktu),
- spójną nazwę.

**Wstecznie:** migracja danych potrzebna, ale nieinwazyjna (tabela można dobudować i wypełnić z `MAX(product_name)`).

---

### 3.3 🟠 Fallback na brak kolumn `issue_target/driver_id/driver_name` — to **martwy kod**
**Plik:** [api/barcode.php](api/barcode.php#L160)

**Zweryfikowane na produkcji 21.04.2026 (`DESCRIBE stock_movements`):** kolumny `issue_target`, `driver_id`, `driver_name` **istnieją**. Catch `PDOException` z fallbackiem na INSERT 11-kolumnowy nigdy się nie aktywuje.

`CLAUDE.md` mówi "nie usuwaj fallbacku" — ale to zalecenie pisane w obawie o instancję, która nie istnieje. Skoro prod = dev = pełny schemat, fallback to defensive coding bez pokrycia + ukrywanie potencjalnych prawdziwych błędów (np. constraint violation — też łapie `PDOException` i próbuje INSERT bez kolumn, co tylko maskuje problem).

**Propozycja:**
- **Usunąć** cały `try/catch` z `handlePost`. Pozostawić jeden INSERT z 14 kolumnami.
- Jeśli paranoja — zostawić fallback, ale dodać `error_log("[stock_movements] Schema fallback triggered: " . $e->getMessage())` przed drugim INSERT, żeby cokolwiek miało szansę zauważyć anomalię. Lepszy jednak wariant pierwszy.
- Zaktualizować `CLAUDE.md` w MagazynApp — zdjąć zapis o konieczności utrzymania fallbacku.

---

### 3.4 🟠 `next_sas` ma race condition
**Plik:** [api/barcode.php](api/barcode.php#L262)

Dwa requesty równoległe → ten sam `SAS-N` → zderzenie nazwy. Mało prawdopodobne (operatorów ~kilku), ale przy hurtowym ręcznym dodawaniu możliwe.

**Propozycja:** dedykowany generator z UNIQUE INDEX po `barcode` + retry, albo osobna tabela sekwencji `sas_counter (last_id INT)` z `UPDATE … last_id = last_id + 1` w transakcji.

---

### 3.5 🟠 Brak indeksu na `(barcode, unit)`
**Plik:** [api/setup_database.sql](api/setup_database.sql#L30)

**Zweryfikowane na produkcji 21.04.2026:** istnieją indeksy `idx_barcode`, `idx_movement_type`, `idx_user_id`, `idx_delivery_id`, `idx_created_at`. Brak indeksu kompozytowego `(barcode, unit)`. Wszystkie GROUP BY w `barcode.php` lecą po `barcode, unit` — dziś temp-sort, przy większej bazie będzie bolić.

**Propozycja:** `ALTER TABLE stock_movements ADD INDEX idx_barcode_unit (barcode, unit);`. Po wprowadzeniu `stock_products` (3.2) odczyt list i tak idzie z PK na nowej tabeli, ale agregaty stanu wciąż po `stock_movements` — indeks zostaje przydatny.

---

### 3.6 🟡 N+1 przy szukaniu części
**Plik:** [api/barcode.php](api/barcode.php#L296)

`?parts=1` skanuje **całe** `stock_movements` z `LIKE '%X%'` po dwóch kolumnach. `LIKE '%X%'` ignoruje indeks. Przy 100k rekordów zacznie być wolne.

**Propozycja:** FULLTEXT INDEX na `product_name` w przyszłej tabeli `stock_products` (po pkt 3.2). Albo prefiksowe wyszukiwanie (`LIKE 'X%'`) jeśli akceptowalne.

---

### 3.7 🟡 `low_stock` ma hardcoded `< 5`
**Plik:** [api/barcode.php](api/barcode.php#L283)

Próg jest stały. Filtr olejów silnikowych `< 5` to mało, śrub `< 5` to dużo. Po wprowadzeniu `stock_products` (pkt 3.2) — kolumna `min_stock` per produkt z fallbackiem na 5.

---

### 3.8 🟡 `workshop.php` dwa zapytania zamiast JOIN
**Plik:** [api/workshop.php](api/workshop.php#L60-L78)

`workshop_services_groups` + osobne `SELECT * FROM workshop_services_names` i merge w PHP. Można jednym zapytaniem (LEFT JOIN przez JSON_TABLE w MySQL 8). Mikrooptymalizacja.

---

## 4. UX / funkcjonalność

### 4.1 🟠 Brak edycji/anulowania ruchu
Operator wybierze zły produkt → musi wydać korygująco "out", potem "in". Brak flagi `cancelled` lub osobnej akcji "korekta".

**Propozycja:** kolumna `corrected_by INT NULL FK -> stock_movements.id`. UI: w historii produktu przycisk "Skoryguj" → tworzy odwrotny ruch + ustawia `corrected_by`. Raporty filtrują pary skorygowane.

---

### 4.2 🟠 Brak fotografii usterki przy naprawie
**Plik:** [flutter_app/lib/screens/repair_form_screen.dart](flutter_app/lib/screens/repair_form_screen.dart)

`RepairFormScreen` ma OCR tablicy, ale nie zapisuje zdjęcia z kamery. W warsztacie często jest potrzeba dowodu (przed/po, awaria).

**Propozycja:** `image_picker` (jest już `camera`) + upload do API z multipart, zapis ścieżki do `workshop_services.photos JSON`. Offline → kolejka z plikiem (uwaga: rozmiar SQLite/dysku).

---

### 4.3 🟠 Brak druku/etykiet dla SAS-N
Po wygenerowaniu SAS-N nie ma jak nakleić kodu. Operator ręcznie pisze marker. Bluetooth printer (Zebra/Brother) mocno przyspieszyłby pracę.

**Propozycja:** integracja z `esc_pos_bluetooth` lub PDF do druku. Wybór drukarki w `SettingsScreen`.

---

### 4.4 � Brak licznika prób per IP w `auth.php` — **nieistotne w LAN-only**
**Plik:** [api/auth.php](api/auth.php#L72)

W LAN/VPN brute-force per email z różnych IP nie jest realistycznym wektorem (wąska pula adresów, znani użytkownicy). Per-user rate-limit, który już jest, wystarczy.

---

### 4.5 🟡 Loading skeletony zamiast `CircularProgressIndicator`
Skeleton loaders (`shimmer`) na `StockScreen`/`HistoryScreen` znacznie poprawiają wrażenie szybkości. Niskorezolucyjne urządzenia w terenie odczują.

---

### 4.6 🟡 Wyszukiwarka w `StockScreen` nie wyróżnia trafienia
Pull-to-refresh jest, ale brak highlight po której nazwie/kodzie wpadło. Drobiazg, ale poprawia czytelność.

---

### 4.7 🟡 `BatchIssueScreen` — brak "kolejki sukcesów"
Wsadowe wydanie zwraca raport "X z Y wydane". Niewydane zostają w liście? Warto rozjaśnić: zostawić czerwone wpisy z błędami i guzikiem "Spróbuj ponownie".

---

### 4.8 🟡 Powiadomienia push o niskim stanie
Aktualnie `low_stock` widoczne tylko po wejściu do ekranu. Push notification (FCM lub lokalny scheduler) "5 produktów poniżej minimum" raz dziennie dla magazyniera.

---

### 4.9 🟡 Eksport historii ruchów do CSV/PDF z poziomu Fluttera
W warsztacie czasem trzeba pokazać szefowi listę. Gotowe pakiety (`pdf`, `csv`) — szybkie.

---

### 4.10 🟡 Skaner kodów jednocześnie nie czyta QR
**Plik:** [flutter_app/lib/screens/scanner_screen.dart](flutter_app/lib/screens/scanner_screen.dart)

`mobile_scanner` z domyślną konfiguracją obsługuje QR, ale nie ma w UI informacji ani osobnego trybu. Kody QR często są na fakturach / WZ.

**Propozycja:** dodać czytanie WZ z QR (np. JSON z polami) → autouzupełnienie produktów.

---

## 5. DX / proces

### 5.1 🟠 Brak testów
**Plik:** [flutter_app/test/widget_test.dart](flutter_app/test/widget_test.dart)

`CLAUDE.md` świadomie odpuszcza, ale logika kolejki offline + parser tablic to top kandydaci na unit testy. Nie ekrany — same serwisy.

**Propozycja:**
- `OfflineQueueService` — test na sekwencję enqueue/sync z mock'iem `ApiService`.
- `CodeType.detect()` — table-driven test (EAN-13, UPC-A, SAS-N, alfanumeryki).
- `PlateScannerScreen` regex — kanoniczne polskie tablice (PO, WA, BI, alfanumeryczne).

---

### 5.2 🟠 `ApiService` rozproszony po 2 plikach + brak warstwy DTO
Modele zwracane jako `Map<String, dynamic>` — typowanie w runtime, brak kompilacyjnej kontroli. Dodanie `Product`, `StockMovement`, `Repair` jako modele typowane (`freezed` lub ręczne) zmniejsza ryzyko `null check`.

---

### 5.3 🟡 CI/CD
Brak `.github/workflows/`. Minimum: `flutter analyze` + `dart format --set-exit-if-changed` na PR. Build APK debug do artefaktu.

---

### 5.4 🟡 `PODSUMOWANIE.md` rośnie szybciej niż jest aktualizowane
Sugestia: trzymać tylko architekturę + linki do plików, a stan funkcji generować skryptem (np. listing screens/services + parsowanie komentarzy).

---

### 5.5 🟡 Brak observability
`error_log` PHP rzuca w domyślne `php_errors.log` na serwerze. Brak metryk: ile requestów / czas / błędy. Dla LAN minimum: prosty plik logów rotujący na poziomie API + endpoint `/health` (status DB + ms). Dla aplikacji: Sentry-lite (np. `sentry_flutter` — pkt o nowych deps należy uzgodnić).

---

## 6. Schemat DB — drobiazgi

### 6.1 🟡 `INDEX idx_movement_type` o niskiej selektywności
**Plik:** [api/setup_database.sql](api/setup_database.sql#L31)

**Potwierdzone na produkcji** — indeks istnieje (MUL na `movement_type`). `movement_type` ma 2 wartości — cardinality ~2, planner i tak go zignoruje przy GROUP BY, koszt utrzymania przy INSERT pozostaje. Do usunięcia: `ALTER TABLE stock_movements DROP INDEX idx_movement_type;`. Zostawić tylko jeśli wprowadzi się indeks kompozytowy `(movement_type, created_at)` pod konkretne raporty.

### 6.2 🟡 `quantity DECIMAL(10,2)` przy `unit='szt'`
Na sztuki wystarczy `INT`. Na `kg/l` `DECIMAL(10,3)` byłoby precyzyjniejsze. Można podzielić kolumny lub dopisać reguły walidacji.

### 6.3 🟡 Kolumna `code_type` w `stock_movements` — duplikacja
Jeśli `barcode` zaczyna się od `SAS-` to `code_type=product_code`, w innym przypadku `barcode`. Po wprowadzeniu `stock_products` (pkt 3.2) trzymać tam, nie w każdym ruchu.

### 6.4 🟡 Brak FK
**Potwierdzone na produkcji** — `user_id` i `delivery_id` mają indeks (MUL), ale brak FK. `driver_id` też bez FK. Brak ON DELETE RESTRICT/SET NULL na `users`/`employees`/`stock_deliveries` — osierocone rekordy możliwe (np. usunięty pracownik → ruchy z `driver_id` wskazują w próżnię, jeśli twardy DELETE; soft-delete `deleted=1` to ratuje, ale nie ma gwarancji).

---

## 7. Zależności

| Pakiet | Aktualnie | Status | Rekomendacja |
|---|---|---|---|
| `mobile_scanner` | ^5.1.1 | v6 dostępne, breaking | sprawdzić zmiany — niski priorytet |
| `flutter_lints` | ^3.0.1 | v4 stable | safe upgrade |
| `connectivity_plus` | ^6.0.3 | OK | — |
| `sqflite` | ^2.3.0 | v2.4 dostępne | safe |
| `google_mlkit_text_recognition` | ^0.14.0 | major changes — uważać | osobny ticket |
| brak `intl` | — | format dat ręczny | dodać `intl` (oszczędzi formatowania w `HistoryScreen`) — zgodnie z `CLAUDE.md` PYTAJ |
| brak `flutter_secure_storage` | — | wymagane wg pkt 1.3 | osobny ticket |

---

## 8. Priorytetyzacja (sprint-friendly)

### Sprint 1 — fundament danych + audyt (LAN-only)
- 3.1 `client_created_at` (psuje historię offline — najwyższy zwrot)
- 3.2 Tabela `stock_products` (rozwiązuje rename + min_stock + alias)
- 3.5 Indeks `(barcode, unit)`
- 1.1 Tokeny + middleware `require_auth` (audytowe — wiarygodność historii ruchów, nie ochrona przed światem)

### Sprint 2 — refaktor Fluttera
- 2.1 `ApiService` jako singleton + interceptor
- 2.2 Spójna obsługa wyjątków (usunąć `catch (_)`)
- 2.3 Centralizacja URL
- 3.4 Race condition `next_sas`

### Sprint 3 — UX / nowe funkcje
- 4.1 Korekta ruchu
- 4.2 Zdjęcia naprawy
- 4.3 Druk etykiet SAS
- 4.7 Lepszy raport batch (retry niewydanych)
- 5.1 Testy `OfflineQueueService`/`CodeType`/regex tablic

### Sprint 4 — nice-to-have
- 1.2 Hasło DB poza repo (higiena)
- 1.3 `flutter_secure_storage` (po pkt 1.1)
- 4.8 Push o niskim stanie
- 4.9 Eksport CSV/PDF
- 5.5 Endpoint `/health` + log rotujący

---

## 9. Czego **nie ruszać** bez decyzji właściciela

Zgodnie z `CLAUDE.md`:
- żadne `pub upgrade` / nowe deps bez pytania (dotyczy 1.3, 4.2, 4.3, 4.5, 4.8, 4.9, 5.5);
- żadne zmiany w `setup_database.sql` niezgodne z prod (3.1, 3.2, 3.4, 3.5, 6.x — wymagają migracji uzgodnionej z DBA / 192.168.1.42);
- `version` w `pubspec.yaml` zostawić — bumpuje się przy release;
- wsteczna kompatybilność z userami offline (każdy bump v6 → v7 musi mieć migrację — pkt 2.5).

---

*Wnioski oparte na inspekcji kodu z 21.04.2026. Ten plik jest dokumentem startowym do przeglądu — przed implementacją zweryfikuj punkt z właścicielem produktu.*
