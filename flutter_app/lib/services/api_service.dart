import 'dart:convert';
import 'package:http/http.dart' as http;
import '../l10n/translations.dart';
import '../models/code_type.dart';
import 'auth_service.dart';

/// Serwis do komunikacji z API na serwerze LogisticsERP
class ApiService {
  // ======================================================
  // KONFIGURACJA - dostosuj do swojego serwera
  // ======================================================
  static const String _baseUrl = 'http://192.168.1.42';
  static const String _apiPath = '/barcode_api/barcode.php';

  static String get _endpoint => '$_baseUrl$_apiPath';

  /// Zarejestruj ruch magazynowy (przyjęcie lub wydanie).
  ///
  /// [movementType] — 'in' (przyjęcie) lub 'out' (wydanie)
  /// [note] — opcjonalna notatka (np. "Mechanik Kowalski")
  static Future<Map<String, dynamic>> saveProduct({
    required String barcode,
    required String productName,
    required double quantity,
    required String unit,
    required CodeType codeType,
    required String movementType,
    String? note,
    String? issueReason,
    String? vehiclePlate,
    String? issueTarget,
    int? driverId,
    String? driverName,
    String? locationRack,
    int? locationShelf,
    double? minQuantity,
  }) async {
    try {
      final body = <String, dynamic>{
        'barcode': barcode,
        'product_name': productName,
        'quantity': quantity,
        'unit': unit,
        'code_type': codeType.apiValue,
        'movement_type': movementType,
      };
      if (note != null && note.trim().isNotEmpty) {
        body['note'] = note.trim();
      }
      if (issueReason != null && issueReason.isNotEmpty) {
        body['issue_reason'] = issueReason;
      }
      if (vehiclePlate != null && vehiclePlate.trim().isNotEmpty) {
        body['vehicle_plate'] = vehiclePlate.trim();
      }
      if (issueTarget != null && issueTarget.isNotEmpty) {
        body['issue_target'] = issueTarget;
      }
      if (driverId != null) {
        body['driver_id'] = driverId;
      }
      if (driverName != null && driverName.isNotEmpty) {
        body['driver_name'] = driverName;
      }
      if (locationRack != null &&
          locationRack.isNotEmpty &&
          locationShelf != null) {
        body['location_rack'] = locationRack;
        body['location_shelf'] = locationShelf;
      }
      if (minQuantity != null && minQuantity >= 0) {
        body['min_quantity'] = minQuantity;
      }

      // Dołącz dane użytkownika
      final auth = AuthService();
      if (auth.userId != null) {
        body['user_id'] = auth.userId;
      }
      if (auth.displayName != null) {
        body['user_name'] = auth.displayName;
      }

      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (data['success'] == true) {
          return data;
        }
        throw ApiException(data['error'] ?? tr('ERROR_UNKNOWN'));
      }

      throw ApiException(
        data['error'] ??
            tr('ERROR_SERVER_STATUS', args: {'code': '${response.statusCode}'}),
      );
    } on http.ClientException {
      throw NetworkException(tr('ERROR_NO_CONNECTION'));
    } on FormatException {
      throw ApiException(tr('ERROR_INVALID_RESPONSE'));
    }
  }

  /// Pobierz stan magazynowy i historię ruchów dla kodu.
  ///
  /// Zwraca mapę z kluczami: data, stock (lista po jednostkach), movements (historia).
  static Future<Map<String, dynamic>?> checkBarcode(String barcode) async {
    try {
      final uri = Uri.parse('$_endpoint?barcode=$barcode');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['exists'] == true) {
          return data;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Pobierz listę wszystkich produktów ze stanami magazynowymi.
  /// Opcjonalnie filtruj po nazwie lub kodzie.
  static Future<List<Map<String, dynamic>>> getStockList(
      {String search = ''}) async {
    try {
      var url = '$_endpoint?list=1';
      if (search.isNotEmpty) {
        url += '&search=${Uri.encodeComponent(search)}';
      }
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['products'] ?? []);
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Pobierz dostępne części (stan > 0) do wyboru w formularzu naprawy.
  static Future<List<Map<String, dynamic>>> getAvailableParts(
      {String search = ''}) async {
    try {
      var url = '$_endpoint?parts=1';
      if (search.isNotEmpty) {
        url += '&search=${Uri.encodeComponent(search)}';
      }
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['parts'] ?? []);
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Pobierz produkty z zerowym lub niskim stanem (alerty).
  static Future<List<Map<String, dynamic>>> getLowStockAlerts() async {
    try {
      final response = await http
          .get(Uri.parse('$_endpoint?low_stock=1'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['items'] ?? []);
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Pobierz następny wolny kod wewnętrzny SAS-N.
  static Future<String> getNextSasCode() async {
    try {
      final response = await http
          .get(Uri.parse('$_endpoint?next_sas=1'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['next_code'] != null) {
          return data['next_code'] as String;
        }
      }
      return 'SAS-1';
    } catch (_) {
      return 'SAS-1';
    }
  }

  /// Pobierz listę kierowców (aktywnych pracowników) z systemu ERP.
  static Future<List<Map<String, dynamic>>> getDrivers(
      {String search = ''}) async {
    try {
      var url = '$_endpoint?drivers=1';
      if (search.isNotEmpty) {
        url += '&search=${Uri.encodeComponent(search)}';
      }
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['drivers'] ?? []);
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Zmień nazwę produktu (aktualizuje product_name we wszystkich ruchach z danym barcode).
  static Future<bool> renameProduct({
    required String barcode,
    required String newName,
  }) async {
    try {
      final response = await http
          .put(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'barcode': barcode,
              'new_name': newName,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['success'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Ustaw lokalizację produktu (regał + półka). Aby wyczyścić — przekaż null/null.
  ///
  /// Rzuca [ApiException] dla błędów walidacji/biznesowych (4xx)
  /// oraz [NetworkException] dla błędów sieci/timeoutu/5xx.
  static Future<void> setProductLocation({
    required String barcode,
    required String? rack,
    required int? shelf,
  }) async {
    try {
      final response = await http
          .put(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'action': 'set_location',
              'barcode': barcode,
              'location_rack': rack,
              'location_shelf': shelf,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        if (data['success'] == true) return;
        throw ApiException(data['error'] ?? tr('ERROR_UNKNOWN'));
      }
      if (response.statusCode >= 400 && response.statusCode < 500) {
        throw ApiException(data['error'] ?? tr('ERROR_UNKNOWN'));
      }
      throw NetworkException(
        tr('ERROR_SERVER_STATUS', args: {'code': '${response.statusCode}'}),
      );
    } on http.ClientException {
      throw NetworkException(tr('ERROR_NO_CONNECTION'));
    } on FormatException {
      throw ApiException(tr('ERROR_INVALID_RESPONSE'));
    }
  }

  /// Ustaw lub usuń minimalny stan magazynowy dla pary (barcode, unit).
  ///
  /// Przekazanie [minQuantity] = null usuwa ustawienie (wyłącza alert).
  /// Rzuca [ApiException] dla błędów 4xx, [NetworkException] dla sieci/5xx.
  static Future<void> setMinQuantity({
    required String barcode,
    required String unit,
    required double? minQuantity,
  }) async {
    try {
      final auth = AuthService();
      final body = <String, dynamic>{
        'action': 'set_min_quantity',
        'barcode': barcode,
        'unit': unit,
        'min_quantity': minQuantity,
      };
      if (auth.userId != null) {
        body['user_id'] = auth.userId;
      }

      final response = await http
          .put(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        if (data['success'] == true) return;
        throw ApiException(data['error'] ?? tr('ERROR_UNKNOWN'));
      }
      if (response.statusCode >= 400 && response.statusCode < 500) {
        throw ApiException(data['error'] ?? tr('ERROR_UNKNOWN'));
      }
      throw NetworkException(
        tr('ERROR_SERVER_STATUS', args: {'code': '${response.statusCode}'}),
      );
    } on http.ClientException {
      throw NetworkException(tr('ERROR_NO_CONNECTION'));
    } on FormatException {
      throw ApiException(tr('ERROR_INVALID_RESPONSE'));
    }
  }

  /// Pobierz lokalizację produktu po kodzie (funkcja "lupa").
  ///
  /// Zwraca mapę `{barcode, product_name, unit, location_rack, location_shelf}`
  /// gdy produkt istnieje (lokalizacja może być null), lub `null` gdy nie istnieje.
  /// Rzuca [NetworkException] przy braku łączności.
  static Future<Map<String, dynamic>?> getProductLocation(
      String barcode) async {
    try {
      final uri =
          Uri.parse('$_endpoint?location=${Uri.encodeComponent(barcode)}');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true) {
          if (data['exists'] == true && data['product'] != null) {
            return Map<String, dynamic>.from(data['product'] as Map);
          }
          return null;
        }
      }
      throw NetworkException(
        tr('ERROR_SERVER_STATUS', args: {'code': '${response.statusCode}'}),
      );
    } on http.ClientException {
      throw NetworkException(tr('ERROR_NO_CONNECTION'));
    } on FormatException {
      throw ApiException(tr('ERROR_INVALID_RESPONSE'));
    }
  }
}

/// Wyjątek rzucany w przypadku błędów API (biznesowych)
class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

/// Wyjątek rzucany w przypadku błędów sieciowych
class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);

  @override
  String toString() => message;
}
