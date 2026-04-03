import 'dart:convert';
import 'package:http/http.dart' as http;

/// Serwis komunikacji z API warsztatowym (naprawy, naczepy, pojazdy).
class WorkshopApiService {
  static const String _baseUrl = 'http://192.168.1.42';
  static const String _apiPath = '/barcode_api/workshop.php';

  static String get _endpoint => '$_baseUrl$_apiPath';

  /// Wyszukaj pojazd/naczepę po tablicy rejestracyjnej.
  static Future<Map<String, dynamic>> searchByPlate(String plate) async {
    try {
      final uri = Uri.parse('$_endpoint?plate=${Uri.encodeComponent(plate)}');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'error': 'Brak połączenia z serwerem'};
    }
  }

  /// Pobierz listę pracowników.
  static Future<List<Map<String, dynamic>>> getEmployees() async {
    try {
      final uri = Uri.parse('$_endpoint?employees=1');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        return List<Map<String, dynamic>>.from(data['employees'] ?? []);
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Pobierz listę usług warsztatowych pogrupowanych (type: 1=pojazd, 2=naczepa).
  static Future<List<Map<String, dynamic>>> getServiceGroups(int objectType) async {
    try {
      final uri = Uri.parse('$_endpoint?services=1&type=$objectType');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        return List<Map<String, dynamic>>.from(data['groups'] ?? []);
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Dodaj nową naprawę.
  static Future<Map<String, dynamic>> addRepair({
    required int objectId,
    required int objectType,
    required String date,
    required int employeeId,
    int mileage = 0,
    double laborCost = 0,
    String note = '',
    int userId = 0,
    List<Map<String, dynamic>>? services,
    List<Map<String, dynamic>>? customServices,
  }) async {
    try {
      final body = {
        'object_id': objectId,
        'object_type': objectType,
        'date': date,
        'employee_id': employeeId,
        'mileage': mileage,
        'labor_cost': laborCost,
        'note': note,
        'user_id': userId,
        if (services != null) 'services': services,
        if (customServices != null) 'custom_services': customServices,
      };

      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'error': 'Brak połączenia z serwerem'};
    }
  }
}
