import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Web talks to localhost; Android emulator reaches your PC at 10.0.2.2.
// On a real phone use your PC's LAN IP, e.g. http://192.168.1.50:4000
const _apiEnv = String.fromEnvironment('API_URL');
// production web build uses API_URL=same -> talks to whatever domain served the page
String get baseUrl => _apiEnv == 'same'
    ? Uri.base.origin
    : (_apiEnv.isNotEmpty ? _apiEnv : (kIsWeb ? 'http://localhost:4000' : 'http://10.0.2.2:4000'));

class Api {
  static const _store = FlutterSecureStorage();
  static String? token;

  static Future<void> loadToken() async => token = await _store.read(key: 'token');

  static Future<void> logout() async {
    token = null;
    await _store.delete(key: 'token');
  }

  static Map<String, String> get _h => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  /// returns null on success, error text on failure
  static Future<String?> auth(String path, String phone, String pass) async {
    try {
      final r = await http.post(Uri.parse('$baseUrl/api/auth/$path'),
          headers: _h, body: jsonEncode({'phone': phone, 'password': pass}));
      final j = jsonDecode(r.body);
      if (r.statusCode != 200) return (j['error'] ?? 'error').toString();
      token = j['token'];
      await _store.write(key: 'token', value: token);
      return null;
    } catch (_) {
      return 'Cannot reach server';
    }
  }

  static Future<List<dynamic>> topWins() async {
    try {
      final r = await http.get(Uri.parse('$baseUrl/api/top-wins'));
      return jsonDecode(r.body);
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> withdraw(String method, String destination, int amount) async {
    final r = await http.post(Uri.parse('$baseUrl/api/pay/withdraw'),
        headers: _h, body: jsonEncode({'method': method, 'destination': destination, 'amount': amount}));
    return jsonDecode(r.body);
  }

  static Future<int> balance() async {
    final r = await http.get(Uri.parse('$baseUrl/api/me/balance'), headers: _h);
    return jsonDecode(r.body)['balance'] as int;
  }

  static Future<Map<String, dynamic>> deposit(String method, int amount) async {
    final r = await http.post(Uri.parse('$baseUrl/api/pay/deposit'),
        headers: _h, body: jsonEncode({'method': method, 'amount': amount}));
    return jsonDecode(r.body);
  }

  static Future<List<dynamic>> bets() async {
    final r = await http.get(Uri.parse('$baseUrl/api/me/bets'), headers: _h);
    return jsonDecode(r.body);
  }
}