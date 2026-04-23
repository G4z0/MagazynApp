# AGENT.md — MagazynApp (Warsztat - LogisticsERP)

Ten plik opisuje, jak pracować w tym repo. Czytaj go przed każdą większą zmianą.
Aktualny stan projektu (ekrany, serwisy, endpointy, schemat DB) jest w `PODSUMOWANIE.md` — traktuj ten plik jako źródło prawdy o **architekturze**, a `AGENT.md` jako źródło prawdy o **sposobie pracy**.

---

## 1. Kontekst w jednym akapicie

Flutter 3.41.1 (Dart 3.11) + PHP/MySQL. Aplikacja produkcyjna, wersja 1.2.1+4, używana terenowo w warsztacie/magazynie. Kluczowe: **praca offline jest obowiązkowa** — operatorzy tracą zasięg przy regałach i w blaszanych halach. Backend to LAN (192.168.1.42), autoryzacja bcrypt + token w `SharedPreferences`. 5 języków (PL/EN/UA/RU/KA), Material 3 Dark, akcent `#3498DB`.

---

## 2. Zasady bezwzględne (nigdy nie łam bez zgody)

1. **Nie dodawaj nowych zależności do `pubspec.yaml` bez pytania.** Każdy pakiet to kolejny wektor utrzymania i potencjalny konflikt z `mobile_scanner`/`camera`/`google_mlkit_text_recognition`, które są wrażliwe na wersje.
2. **Nie usuwaj fallbacku do kolejki offline** z żadnego miejsca, które zapisuje dane. Jeśli dodajesz nowy endpoint POST/PUT — musi mieć ścieżkę `NetworkException → OfflineQueueService.enqueue()`.
3. **Nie wprowadzaj zmian w schemacie `offline_queue.db` bez migracji.** Baza jest na wersji 6, userzy w terenie mogą mieć dowolną wersję pośrednią. Każda zmiana schematu = bump wersji + migracja w `onUpgrade`.
4. **Nie dodawaj kluczy tłumaczeń tylko w PL.** Każdy nowy `tr('KEY')` musi być uzupełniony we wszystkich 5 językach w `lib/l10n/translations.dart`. Jeśli nie znasz tłumaczenia na ukraiński/rosyjski/gruziński — zostaw klucz po angielsku i **oznacz to w komentarzu**, żeby user mógł uzupełnić.
5. **Nie loguj danych wrażliwych** (token sesji, hasło, pełne dane kierowcy) do konsoli ani do `LocalHistoryService`. Historia lokalna jest dla akcji biznesowych, nie debugu.

---

## 3. Konwencje kodu

### Struktura warstw
- `screens/` — tylko UI + orkiestracja. Bez bezpośrednich zapytań HTTP, bez bezpośredniego SQL.
- `services/` — cała logika I/O. Singletony (tak jak `AuthService`, `OfflineQueueService`). Każdy serwis rzuca `ApiException` (błąd biznesowy) lub `NetworkException` (brak sieci) — **nigdy gołego `Exception`**.
- `models/` — czyste klasy danych, bez logiki I/O. Obecnie prawie puste (`CodeType`) — rozrasta się, jeśli dodajesz nowe encje.

### Obsługa błędów w ekranach
Każdy ekran zapisujący dane musi mieć ten sam szablon:
```dart
try {
  await ApiService().saveProduct(...);
  await LocalHistoryService().add(...);
  if (mounted) Navigator.pop(context, true);
} on ApiException catch (e) {
  // Błąd biznesowy (walidacja, brak stanu) — pokaż userowi, nie kolejkuj
  _showError(e.message);
} on NetworkException {
  // Brak sieci — do kolejki offline
  await OfflineQueueService().enqueue(...);
  _showOfflineDialog();
}
```
Nie skracaj tego do `catch (e)`. Klasy wyjątków są rozróżniane celowo.

### Stan
- Proste ekrany → `setState`.
- Stan współdzielony między ekranami → `ValueNotifier` (tak jak `pendingCount` w `OfflineQueueService`).
- **Nie wprowadzaj** Riverpod/BLoC/Provider bez osobnej dyskusji — to byłaby duża refaktoryzacja, nie pojedyncza zmiana.

### i18n
- Zawsze `tr('KEY')`, nigdy stringi literałowe w UI.
- Klucze w `SCREAMING_SNAKE_CASE`, pogrupowane prefiksem ekranu (np. `SCANNER_HINT_ALIGN_CODE`).
- Argumenty: `tr('LOW_STOCK_WARNING', args: {'count': '5'})`.

### Nazewnictwo
- Ekrany: `*Screen` (np. `BatchIssueScreen`).
- Serwisy: `*Service` (np. `OfflineQueueService`).
- Wyjątki: `*Exception` (np. `ApiException`).
- Pliki: `snake_case.dart`.

---

## 4. Checklisty dla typowych zadań

### Dodaję nowy endpoint w API + użycie we Flutterze
- [ ] Endpoint w odpowiednim pliku PHP (`barcode.php` / `workshop.php` / nowy?).
- [ ] Walidacja wejścia po stronie PHP (długości, typy, obowiązkowe pola).
- [ ] Transakcja DB, jeśli zapis dotyka > 1 tabeli.
- [ ] Metoda w odpowiednim `*ApiService` z `ApiException`/`NetworkException`.
- [ ] Jeśli to POST/PUT — ścieżka do kolejki offline.
- [ ] Jeśli odpowiedź zmienia stan magazynu — odświeżenie w `StockScreen` (pull-to-refresh wystarcza? czy trzeba aktywnie?).
- [ ] Nowe klucze tłumaczeń dla komunikatów błędów (5 języków).
- [ ] Test ręczny z wyłączonym WiFi.

### Dodaję nowy ekran
- [ ] Plik w `lib/screens/nazwa_screen.dart`.
- [ ] Wszystkie stringi przez `tr()`.
- [ ] Jeśli ekran pokazuje dane z API — obsłuż stany: loading, error, empty, success.
- [ ] Jeśli ekran ma formularz — obsłuż `NetworkException` z dialogiem "zapisano offline".
- [ ] Dodaj wpis do `LocalHistoryService` dla każdej akcji biznesowej (typy: `stock_in`, `stock_out`, `scan`, `login`, `logout`, `repair_add` — jeśli potrzebujesz nowego, dodaj do enum).
- [ ] Nawigacja z `HomeScreen` / `SettingsScreen` / skąd trzeba.

### Zmieniam schemat bazy offline
- [ ] Bump wersji w `OfflineQueueService` (obecnie 6 → 7).
- [ ] `onUpgrade` obsługuje przejście ze WSZYSTKICH poprzednich wersji (1→7, 2→7, …, 6→7), nie tylko 6→7.
- [ ] Testowy scenariusz: świeża instalacja + upgrade z v6.

### Refaktor wielu plików
- [ ] Najpierw `flutter analyze`, zapisz baseline.
- [ ] Zmiana.
- [ ] `flutter analyze` — zero nowych ostrzeżeń.
- [ ] `flutter test` (jeśli są testy; obecnie prawie brak — nie dodawaj "przy okazji", to osobny temat).
- [ ] `dart format lib/`.

---

## 5. Znane pułapki tego projektu

**Skaner tablic (`PlateScannerScreen`)**
Regex `^[A-Z]{1,3}\s?[A-Z0-9]{2,5}$` daje fałszywe negatywy na O/0 i I/1. Jeśli user zgłasza "nie rozpoznaje mojej tablicy" — najpierw zrzuć surowy wynik OCR, nie zmieniaj regexa na ślepo.

**`mobile_scanner` a `camera`**
Oba używają kamery. Nie otwieraj ich jednocześnie — na Androidzie potrafi zawiesić aplikację. Przy przejściu `ScannerScreen` → `OcrCaptureScreen` **zawsze** dispose'uj kontroler poprzedniego.

**Kolejka offline a błędy biznesowe**
`OfflineQueueService.syncQueue()` rozróżnia błędy sieciowe (zostaw, ponów) od biznesowych (usuń z kolejki). Jeśli dodajesz nowy typ błędu po stronie API — zadbaj, żeby zwracał właściwy kod HTTP (4xx = biznesowy, 5xx/timeout = sieciowy), inaczej zepsujesz logikę retry.

**`shared_preferences` a token sesji**
Token jest w plaintext w `SharedPreferences`. To **znany kompromis**, nie błąd do naprawy "przy okazji". Migracja do `flutter_secure_storage` = osobny ticket, wymaga decyzji o wstecznej kompatybilności z istniejącymi sesjami.

**CORS `*` + HTTP w LAN**
API działa na `http://192.168.1.42` z `Access-Control-Allow-Origin: *`. Świadome — to LAN firmowy. **Nie proponuj** wyrzucenia CORS ani wymuszania HTTPS bez rozmowy o wdrożeniu.

**`stock_movements` — fallback na starszą strukturę**
Backend ma `try/catch` na brak kolumn `issue_target`/`driver_id`/`driver_name`. Oznacza to, że w jakiejś instancji bazy te kolumny mogą nie istnieć. Nie usuwaj fallbacku.

**Auto-detekcja `CodeType`**
`CodeType.detect()` decyduje między `barcode` a `product_code` na podstawie zawartości. Zmiana tej heurystyki wpływa na to, gdzie produkt trafia w bazie — testuj zarówno EAN-13, UPC-A, jak i wewnętrzne kody SAS-N.

---

## 6. Czego NIE robić bez pytania

- Nie uruchamiaj `flutter pub upgrade` — `mobile_scanner` i `google_mlkit_text_recognition` mają breaking changes między major wersjami.
- Nie zmieniaj wersji w `pubspec.yaml` (`1.2.1+4`) — to robi się przy release, nie w trakcie pracy.
- Nie twórz plików w `assets/` bez dodania ich do `pubspec.yaml` (i odwrotnie).
- Nie dotykaj `api/setup_database.sql` w sposób niezgodny z aktualnym schematem produkcyjnym — ten plik musi odpowiadać temu, co jest na 192.168.1.42.
- Nie pisz testów "przy okazji" zmiany. Jeśli uważasz, że coś powinno być przetestowane, zgłoś to jako osobny temat.
- Nie commituj za usera. Pokaż `git diff`, zaproponuj wiadomość commita, ale `git commit` wywołuje user.

---

## 7. Komendy, które możesz wywoływać swobodnie

```bash
flutter analyze
flutter pub get
flutter pub outdated           # tylko do odczytu
dart format lib/
dart format --set-exit-if-changed lib/   # check bez modyfikacji
flutter test
flutter build apk --debug      # tylko gdy user prosi o build
```

Komendy, które wymagają zgody:
- `flutter pub upgrade` / `flutter pub add` / `flutter pub remove`
- `flutter clean`
- cokolwiek, co pisze do `api/` na serwerze
- `git commit`, `git push`, `git rebase`, `git reset --hard`

---

## 8. Jak zgłaszać mi niejasności

Jeśli zadanie jest niedoprecyzowane — **najpierw zapytaj**, nie zgaduj. Szczególnie:
- czy zmiana ma dotyczyć tylko Fluttera, czy też API/DB,
- czy zmiana ma być kompatybilna wstecz z userami, którzy mają starszą wersję aplikacji w terenie,
- czy nowy klucz tłumaczenia ma mieć profesjonalne brzmienie warsztatowe, czy luźniejsze (PL branżowe vs neutralne).

---

## 9. Struktura repo (skrót, pełna w `PODSUMOWANIE.md`)

```
MagazynApp/
├── api/                    # PHP backend (LAN, 192.168.1.42)
├── flutter_app/
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart
│   │   ├── l10n/translations.dart
│   │   ├── models/
│   │   ├── screens/        # 12 ekranów
│   │   └── services/       # 5 serwisów-singletonów
│   └── assets/
├── PODSUMOWANIE.md         # pełny opis stanu aplikacji
├── CLAUDE.md               # ten plik
├── INSTRUKCJA.md
└── README.md
```
