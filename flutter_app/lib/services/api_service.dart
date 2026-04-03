import 'dart:convert';
import 'package:http/http.dart' as http;
import '../l10n/translations.dart';
import '../models/code_type.dart';

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

      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json'},
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
        data['error'] ?? tr('ERROR_SERVER_STATUS', args: {'code': '${response.statusCode}'}),
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
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));

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
  static Future<List<Map<String, dynamic>>> getStockList({String search = ''}) async {
    try {
      var url = '$_endpoint?list=1';
      if (search.isNotEmpty) {
        url += '&search=${Uri.encodeComponent(search)}';
      }
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

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
  static Future<List<Map<String, dynamic>>> getAvailableParts({String search = ''}) async {
    try {
      var url = '$_endpoint?parts=1';
      if (search.isNotEmpty) {
        url += '&search=${Uri.encodeComponent(search)}';
      }
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

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
