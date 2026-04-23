# Code Review: Funkcjonalność edycji kodów kreskowych i nazw produktów

**Data:** 23.04.2026  
**Projekt:** MagazynApp (Aplikacja logistyczna/magazynowa)  
**Analizowane pliki:** `product_edit_screen.dart`, `api_service.dart`, `offline_queue_service.dart`, `setup_database.sql`, `stock_screen.dart` oraz wstępna `ANALIZA.md`.

---

## 1. Architektura rozwiązania i ogólna ocena
Funkcjonalność edycji tożsamości produktu (kodu kreskowego / nazwy) opiera się na aplikacji Flutter komunikującej się z backendem PHP. Aplikacja posiada wsparcie dla operacji offline (poprzez `OfflineQueueService`), co znacząco komplikuje proces zmian kluczy głównych (takich jak `barcode`).

Rozwiązanie słusznie zmierza w kierunku scentralizowania "kanonicznych" danych o produktach (widok `stock_summary` i planowany słownik `stock_products`), zapobiegając nadpisywaniu tożsamości produktu przez niespójne logi w `stock_movements`. Pojawiają się jednak luki w obsłudze przepływu i spójności stanów w UI.

---

## 2. Zidentyfikowane problemy (Bugs & Vulnerabilities)

### [Wysoki Priorytet] Fałszywy sukces w `ProductEditScreen` (Błąd UI/UX)
W aktualnym przepływie edycji ekran może zakomunikować globalny sukces i zostać zamknięty, pomimo że zapis się nie powiódł w całości.
* **Problem:** Jeśli użytkownik edytuje jednocześnie kod kreskowy i nazwę, a API zwróci błąd dla zmiany nazwy (ale kod się zmieni z sukcesem), ekran ignoruje błąd (pokazując tylko krótkiego snackbara) i zamyka się z komunikatem sukcesu. Flagowanie stanu `didChange = true` powoduje "wyciek" błędu.
* **Skutek:** Użytkownik jest przekonany, że zmienił nazwę, a de facto zmienił tylko kod.

### [Wysoki Priorytet] Brak aktualizacji `code_type` podczas zmiany kodu
* **Problem:** Operacja `change_barcode` nie modyfikuje przypisanego do niego `code_type`. Jeśli użytkownik zmienia typ kodu kreskowego z np. EAN na wewnętrzny `product_code`, w bazie mogą powstać niespójności.
* **Skutek:** System może w przyszłości źle formatować ten kod lub używać złych skanerów w UI z powodu błędnego flagowania.

### [Średni Priorytet] Brak propagacji "Kanonicznego" Barcode
* **Problem:** Po edycji kodu aplikacja kliencka nie pobiera z odpowiedzi API kanonicznej (ostatecznej) wersji barkodu.
* **Skutek:** Lokalne serwisy, takie jak deduplikacja, kolejka offline (`OfflineQueueService`) oraz `LocalHistoryService` mogą operować na przestarzałym aliasie, co spowoduje problemy w przypadku np. braku sieci w kolejnych minutach pracy.

### [Średni Priorytet] Problemy z widokami bazy danych (`setup_database.sql`)
W strukturze `setup_database.sql` widok `stock_summary` wykorzystuje podzapytania, aby wybrać najnowszą nazwę produktu z logu historii `stock_movements`.
* **Problem:** Rozwiązanie typu `ORDER BY ... DESC LIMIT 1` sprawia, że historia ruchów definiuje nam słownik produktów. To zła praktyka. W zaprezentowanym pliku `ANALIZA.md` słusznie zauważono, że należy bazować na `stock_products` jako kanonicznym słowniku. Aktualne podzapytanie w `stock_summary` jest powolne i mało przewidywalne.

---

## 3. Analiza implementacji poszczególnych serwisów

### `OfflineQueueService`
Aktualny model (Tabela `queue`) zakłada zapisywanie ruchów (`action_type = 'save_product'`), ale należy zachować szczególną ostrożność przy zmianie nazwy i kodu offline. Jeśli wprowadzisz akcję `change_barcode` do trybu offline, upewnij się, że inne zdarzenia dodane do kolejki natychmiast po zmianie będą powiązane z NOWYM kodem. 

### `ApiService`
Metoda `saveProduct` przyjmuje pełne encje dla ruchu magazynowego (`barcode`, `product_name`, `code_type` itp.). W przypadku edycji nazwy lub przypisanego kodu, powinieneś wydzielić do tego dedykowane endpointy (np. `updateProductIdentity`), ponieważ mieszanie ruchu na magazynie z edycją atrybutów master-data produktu prowadzi do bałaganu.

---

## 4. Rekomendacje i plan naprawczy

1. **Poprawa State Managementu na ekranie edycji:**
   W `product_edit_screen.dart` użyj operacji transakcyjnej z perspektywy UI. Możesz agregować wszystkie zmiany (`Futures`) w `Future.wait()`. Ekran (oraz proces nawigacji wstecz) może zwrócić "sukces" dopiero po zatwierdzeniu KAŻDEJ obietnicy edycji. W przypadku braku sukcesu w jednym kroku — zatrzymaj ekran i pozwól na ręczne poprawienie błędów lub ponowienie zapisu.

2. **Backend: Spójna obsługa tożsamości (Kanoniczny słownik):**
   Upewnij się, że zmiany nazw i kodów trafiają bezpośrednio do odrębnej tabeli `stock_products` (Słownik). Tabele logów (`stock_movements`) w idealnym scenariuszu nie powinny być w ogóle modyfikowane pod kątem "updatowania starych nazw". Log to fakt historyczny.

3. **Backend: Zwracanie potwierdzonych wartości:**
   API w odpowiedzi na edycję zawsze powinno zwracać pełen, aktualny obiekt towaru (`{ "canonical_barcode": "...", "code_type": "...", "product_name": "..." }`). UI po otrzymaniu tej odpowiedzi musi zainicjować odświeżenie kontekstu w aplikacji.

4. **Wyszukiwarki i Aliasy:**
   Aby alias starego kodu działał w `stock_screen.dart` (pole `_searchController`), endpoint `getStockList` musi wspierać przeszukiwanie powiązanej tabeli/historii aliasów, a nie tylko głównego rekordu.

---
**Podsumowanie:** Ogólny zamysł aplikacji i serwisów jest poprawny (architektura wydzielona na serwisy, kolejka SQLite offline), jednak sama logika modyfikacji tożsamości encji wymaga "uszczelnienia" w zakresie przechwytywania błędów częściowych i solidniejszego przekazywania zaktualizowanych danych z powrotem do aplikacji klienckiej.