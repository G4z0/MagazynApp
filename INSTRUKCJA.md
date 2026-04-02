# Skaner Kodów Kreskowych - LogisticsERP

## Struktura projektu

```
barcode_scanner_app/
├── api/                          ← Pliki do wgrania na serwer 192.168.1.42
│   ├── config.php                ← Konfiguracja bazy danych
│   ├── barcode.php               ← Endpoint API
│   └── setup_database.sql        ← Skrypt tworzenia tabeli
│
├── flutter_app/                  ← Projekt Flutter (aplikacja mobilna)
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart             ← Punkt startowy aplikacji
│   │   ├── services/
│   │   │   └── api_service.dart  ← Komunikacja z API
│   │   └── screens/
│   │       ├── scanner_screen.dart      ← Ekran skanera
│   │       └── product_form_screen.dart ← Formularz nazwy produktu
│   ├── android_permissions.md    ← Konfiguracja Android
│   └── ios_permissions.md        ← Konfiguracja iOS
│
└── INSTRUKCJA.md                 ← Ten plik
```

---

## Krok 1: Konfiguracja serwera (192.168.1.42)

### 1a. Stwórz tabelę w bazie danych
Uruchom skrypt SQL na serwerze:
```bash
mysql -u logisticserp_dev -p logisticserp_dev < setup_database.sql
```

### 1b. Skopiuj pliki API
Skopiuj `config.php` i `barcode.php` na serwer do:
```
/var/www/html/barcode_api/
```
Tak żeby endpoint był dostępny pod:
```
http://192.168.1.42/barcode_api/barcode.php
```

### 1c. Edytuj config.php
Zmień dane dostępowe do bazy w pliku `config.php`:
- DB_NAME - nazwa bazy danych
- DB_USER - użytkownik MySQL
- DB_PASS - hasło

### 1d. Przetestuj API
```bash
# Test zapisu:
curl -X POST http://192.168.1.42/barcode_api/barcode.php \
  -H "Content-Type: application/json" \
  -d '{"barcode":"1234567890","product_name":"Testowy produkt"}'

# Test odczytu:
curl http://192.168.1.42/barcode_api/barcode.php?barcode=1234567890
```

---

## Krok 2: Konfiguracja Flutter

### 2a. Stwórz nowy projekt Flutter
```bash
flutter create barcode_scanner
cd barcode_scanner
```

### 2b. Skopiuj pliki
Zastąp zawartość folderu `lib/` plikami z `flutter_app/lib/`
Zastąp `pubspec.yaml` plikiem z `flutter_app/pubspec.yaml`

### 2c. Zainstaluj zależności
```bash
flutter pub get
```

### 2d. Skonfiguruj uprawnienia
- **Android**: Patrz `android_permissions.md`
- **iOS**: Patrz `ios_permissions.md`

### 2e. Zmień adres serwera (jeśli potrzeba)
W pliku `lib/services/api_service.dart` zmień:
```dart
static const String _baseUrl = 'http://192.168.1.42';
static const String _apiPath = '/barcode_api/barcode.php';
```

### 2f. Uruchom aplikację
```bash
flutter run
```

---

## Jak działa aplikacja

1. Uruchamiasz aplikację → widzisz podgląd kamery ze skanerem
2. Kierujesz kamerę na kod kreskowy
3. Kod jest automatycznie rozpoznawany
4. Otwiera się formularz z polem na nazwę produktu
5. Wpisujesz nazwę i klikasz "Zapisz"
6. Dane (kod + nazwa) są wysyłane do API i zapisywane w bazie MySQL
7. Wracasz do skanera, gotowy na następny kod

Dodatkowo:
- Jeśli kod już istnieje w bazie, nazwa jest wstępnie wypełniona
- Można wpisać kod ręcznie (przycisk "Wpisz ręcznie")
- Lampa błyskowa do skanowania w ciemności
