# Analiza zmian dotyczących edycji produktów

Data: 2026-04-23

## Zakres

Przegląd objął cały przepływ edycji produktu w MagazynApp:

- Flutter UI: ekran edycji produktu, ekran stanów, formularz produktu, batch issue, historia lokalna.
- Serwisy Flutter: `ApiService`, `OfflineQueueService`, `LocalHistoryService`.
- Backend PHP: `api/barcode.php`.
- Schemat bazy: `api/setup_database.sql`.

Analiza dotyczyła przede wszystkim zmian nazwy produktu, zmiany barcode, lokalizacji produktu, korekt ilości oraz wpływu tych operacji na historię i spójność danych.

## Findings

### 1. High: ekran edycji może zakończyć się komunikatem sukcesu mimo częściowo nieudanego zapisu

Po udanej zmianie kodu, nieudany rename nie przerywa przepływu. Ekran tylko pokazuje snackbar błędu, ale jeśli wcześniejszy krok ustawił `didChange = true`, to całość i tak kończy się globalnym komunikatem sukcesu i zamknięciem ekranu.

Miejsca kontrolujące zachowanie:

- `flutter_app/lib/screens/product_edit_screen.dart:347`
- `flutter_app/lib/screens/product_edit_screen.dart:351`
- `flutter_app/lib/screens/product_edit_screen.dart:378`
- `flutter_app/lib/screens/product_edit_screen.dart:422`
- `flutter_app/lib/screens/product_edit_screen.dart:428`

Dodatkowy problem jest w warstwie serwisowej: `renameProduct()` zwraca wyłącznie `true` albo `false` i połyka błędy sieciowe/API, więc UI nie może rozróżnić partial failure od pełnego sukcesu.

Miejsce:

- `flutter_app/lib/services/api_service.dart:241`

Skutek biznesowy:

- użytkownik może zobaczyć "Zapisano zmiany", mimo że np. nazwa produktu nie została faktycznie zmieniona,
- przy wielu operacjach wykonanych jednocześnie ekran nie gwarantuje atomowości z punktu widzenia użytkownika.

### 2. High: zmiana barcode nie aktualizuje `code_type`, więc produkt może zostać z błędnym typem kodu

Backend przy `change_barcode` przepisuje sam `barcode` w tabelach, ale nie aktualizuje `code_type`. Potem każdy kolejny zapis ruchu rozwiązuje produkt po kanonicznym barcode i wymusza stary `code_type` z istniejącego rekordu.

Miejsca kontrolujące zachowanie:

- `api/barcode.php:564`
- `api/barcode.php:568`
- `api/barcode.php:1515`
- `api/barcode.php:1519`
- `api/barcode.php:978`

Skutek biznesowy:

- jeśli użytkownik zmieni kod z EAN na kod wewnętrzny albo odwrotnie, produkt może na stałe pozostać sklasyfikowany jako stary typ,
- późniejsze odczyty list i formularzy mogą pracować na nieaktualnej klasyfikacji produktu.

### 3. Medium: klienci Fluttera ignorują kanoniczny barcode zwracany przez API po rozwiązaniu aliasu

Backend po `GET ?barcode=` zwraca już barcode kanoniczny, ale część klientów Fluttera nadal pracuje na surowo wpisanym lub zeskanowanym kodzie. To prowadzi do niespójności w UI, historii lokalnej i batch issue.

Backend zwraca kanoniczny kod tutaj:

- `api/barcode.php:1131`

Klienci nadal używają starego kodu tutaj:

- `flutter_app/lib/screens/product_form_screen.dart:208`
- `flutter_app/lib/screens/product_form_screen.dart:283`
- `flutter_app/lib/screens/product_form_screen.dart:321`
- `flutter_app/lib/screens/product_form_screen.dart:363`
- `flutter_app/lib/screens/batch_issue_screen.dart:255`
- `flutter_app/lib/screens/batch_issue_screen.dart:355`
- `flutter_app/lib/screens/batch_issue_screen.dart:376`
- `flutter_app/lib/screens/batch_issue_screen.dart:391`
- `flutter_app/lib/screens/batch_issue_screen.dart:412`
- `flutter_app/lib/screens/batch_issue_screen.dart:432`
- `flutter_app/lib/screens/batch_issue_screen.dart:453`

Skutek biznesowy:

- ten sam produkt może pojawić się dwa razy na ekranie batch issue, jeśli raz zostanie zeskanowany stary kod, a raz nowy,
- historia lokalna zapisuje działania pod starym aliasem zamiast pod tożsamością kanoniczną produktu,
- użytkownik dostaje wrażenie, że aplikacja operuje na dwóch różnych produktach, mimo że backend scala je przez alias.

### 4. Medium: aliasy działają dla bezpośredniego lookupu po kodzie, ale nie dla wyszukiwania list i pickerów

Lookup po jednym kodzie jest rozwiązywany do kanonicznego barcode, ale wyszukiwanie listy produktów i listy części nadal filtruje tylko po `sm.barcode` i `sm.product_name` w ruchach magazynowych. To oznacza, że po zmianie kodu wyszukanie produktu po starym barcode może nic nie zwrócić.

Miejsca kontrolujące zachowanie:

- `api/barcode.php:1059`
- `api/barcode.php:917`
- `api/barcode.php:996`

Skutek biznesowy:

- użytkownik może znaleźć produkt po starym kodzie tylko przy bezpośrednim skanie/lookupie,
- ten sam stary kod nie działa już w wyszukiwarce listy stanów lub w pickerze części,
- aliasy są więc wdrożone tylko częściowo i UX pozostaje niespójny.

## Dodatkowe obserwacje

### Kanoniczny odczyt nazw produktów został poprawiony

To jest dobra zmiana. Odczyty list i stanów nie bazują już wyłącznie na losowym `MAX(product_name)` z historii, ale preferują nazwę ze słownika `stock_products`.

Miejsca:

- `api/barcode.php:857`
- `api/barcode.php:905`
- `api/barcode.php:977`
- `api/setup_database.sql:232`

To zmniejsza ryzyko pokazywania przypadkowej nazwy po zmianie produktu.

### Aliasy i change log są sensownym kierunkiem

Nowe tabele:

- `api/setup_database.sql:196` — `stock_product_aliases`
- `api/setup_database.sql:210` — `stock_product_change_log`

To jest właściwy kierunek dla zachowania ciągłości historii przy zmianie barcode i dla rozdzielenia historii biznesowej od historii ruchów magazynowych.

## Warunek krytyczny wdrożenia

Nie uruchamiałem migracji SQL na produkcyjnej bazie.

Dopóki sekcje dotyczące aliasów, logu zmian i końcowej definicji widoku `stock_summary` z `api/setup_database.sql` nie zostaną wykonane na bazie używanej przez API, część zabezpieczeń będzie działała tylko w kodzie aplikacji, ale nie w realnych danych serwera.

Kluczowe miejsca:

- `api/setup_database.sql:196`
- `api/setup_database.sql:210`
- `api/setup_database.sql:232`

## Walidacja techniczna

W ramach przeglądu wykonano walidację statyczną zmienionych plików.

Wynik:

- brak błędów składni PHP w `api/barcode.php`,
- brak błędów analyzera Fluttera w:
  - `flutter_app/lib/screens/product_edit_screen.dart`
  - `flutter_app/lib/screens/stock_screen.dart`
  - `flutter_app/lib/services/offline_queue_service.dart`
  - `flutter_app/lib/services/api_service.dart`

To oznacza, że findings dotyczą logiki i spójności biznesowej, a nie problemów składni albo typów.

## Podsumowanie

Najważniejsze ryzyka po aktualnych zmianach są cztery:

1. UI potrafi zamknąć ekran jako sukces po częściowo nieudanej edycji.
2. `change_barcode` nie przepina `code_type`, więc typ produktu może pozostać błędny.
3. Klienci Fluttera nie przejmują kanonicznego barcode z odpowiedzi API.
4. Alias starego kodu nie działa jeszcze w wyszukiwarkach list i pickerów.

Ogólny kierunek zmian jest dobry: aliasy, change log i kanoniczny słownik produktów rozwiązują wcześniejsze problemy z utratą tożsamości produktu. Natomiast obecna implementacja jest jeszcze niepełna i wymaga domknięcia po stronie UI oraz wyszukiwania.

## Rekomendowane następne kroki

1. Ujednolicić przepływ edycji produktu tak, aby ekran nie zamykał się po partial success.
2. Rozszerzyć `change_barcode` o aktualizację `code_type` i spójne przeliczanie typu kodu po zmianie.
3. Przekazywać kanoniczny barcode z odpowiedzi API dalej przez klienta Flutter i używać go do deduplikacji, historii lokalnej i kolejek.
4. Rozszerzyć wyszukiwanie list produktów i części tak, aby uwzględniało aliasy historycznych kodów.
5. Wykonać migrację SQL na docelowej bazie i przetestować scenariusz: zmiana kodu -> skan starego kodu -> synchronizacja offline.