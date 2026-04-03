import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Serwis autentykacji — logowanie kontem z LogisticsERP (tabela users).
/// Przechowuje sesję w SharedPreferences.
class AuthService {
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;
  AuthService._();

  static const String _baseUrl = 'http://192.168.1.42';
  static const String _authPath = '/barcode_api/auth.php';

  static const String _keyUserId = 'user_id';
  static const String _keyEmail = 'user_email';
  static const String _keyDisplayName = 'user_display_name';
  static const String _keyToken = 'user_token';

  int? _userId;
  String? _email;
  String? _displayName;
  String? _token;

  int? get userId => _userId;
  String? get email => _email;
  String? get displayName => _displayName;
  bool get isLoggedIn => _userId != null && _token != null;

  /// Załaduj zapisaną sesję (wywoływane przy starcie aplikacji)
  Future<bool> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getInt(_keyUserId);
    _email = prefs.getString(_keyEmail);
    _displayName = prefs.getString(_keyDisplayName);
    _token = prefs.getString(_keyToken);
    return isLoggedIn;
  }

  /// Zaloguj się kontem ERP
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl$_authPath'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        final user = data['user'] as Map<String, dynamic>;
        _userId = user['id'] as int;
        _email = user['email'] as String;
        _displayName = user['display_name'] as String;
        _token = user['token'] as String;

        // Zapisz sesję
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_keyUserId, _userId!);
        await prefs.setString(_keyEmail, _email!);
        await prefs.setString(_keyDisplayName, _displayName!);
        await prefs.setString(_keyToken, _token!);

        return {'success': true};
      }

      return {'success': false, 'error': data['error'] ?? 'Błąd logowania'};
    } on http.ClientException {
      return {'success': false, 'error': 'Brak połączenia z serwerem'};
    } catch (e) {
      debugPrint('Login error: $e');
      return {'success': false, 'error': 'Błąd połączenia z serwerem'};
    }
  }

  /// Wyloguj użytkownika
  Future<void> logout() async {
    _userId = null;
    _email = null;
    _displayName = null;
    _token = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyDisplayName);
    await prefs.remove(_keyToken);
  }
}
