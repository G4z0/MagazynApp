import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/code_type.dart';

/// Serwis do komunikacji z API na serwerze LogisticsERP
class ApiService {
  // ======================================================
  // KONFIGURACJA - dostosuj do swojego serwera
  // ======================================================
  static const String _baseUrl = 'http://192.168.1.42';
  static const String _apiPath = '/barcode_api/barcode.php';

  static String get _endpoint => '$_baseUrl$_apiPath';

  /// Zapisz kod kreskowy z nazwą produktu do bazy danych.
  ///
  /// Zwraca [Map] z odpowiedzią API w przypadku sukcesu,
  /// lub rzuca wyjątek w przypadku błędu.
  static Future<Map<String, dynamic>> saveProduct({
    required String barcode,
    required String productName,
    required double quantity,
    required String unit,
    required CodeType codeType,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'barcode': barcode,
              'product_name': productName,
              'quantity': quantity,
              'unit': unit,
              'code_type': codeType.apiValue,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (data['success'] == true) {
          return data;
        }
        throw ApiException(data['error'] ?? 'Nieznany błąd');
      }

      throw ApiException(
        data['error'] ?? 'Błąd serwera (${response.statusCode})',
      );
    } on http.ClientException {
      throw NetworkException('Brak połączenia z serwerem.');
    } on FormatException {
      throw ApiException('Nieprawidłowa odpowiedź z serwera.');
    }
  }

  /// Sprawdź czy kod kreskowy już istnieje w bazie.
  static Future<Map<String, dynamic>?> checkBarcode(String barcode) async {
    try {
      final uri = Uri.parse('$_endpoint?barcode=$barcode');
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['exists'] == true) {
          return data['data'] as Map<String, dynamic>;
        }
      }
      return null;
    } catch (_) {
      return null;
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
