import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'push_notification_service.dart';

/// Persists a signed-in partner, moved out of the OTP screen so the screen only
/// navigates.
///
/// The keys and payload are a contract, not an implementation detail:
///  - `auth_token` is read by every service that calls the API, and by the
///    push service when it registers the device.
///  - `role` and `auth_state` (the whole verify-otp response, JSON-encoded) are
///    read by the splash screen to route a returning partner without a network
///    call, and `auth_state` by the salon picker to prefill "add a salon".
/// Changing any of them signs every installed partner out on next launch.
class AuthSession {
  AuthSession({Future<void> Function()? registerPush})
      : _registerPush = registerPush ?? (() => PushNotificationService().registerDevice());

  final Future<void> Function() _registerPush;

  static const String tokenKey = 'auth_token';
  static const String roleKey = 'role';
  static const String stateKey = 'auth_state';

  /// Save the verify-otp response of an existing partner, then register the
  /// device for push.
  ///
  /// Push registration is started but not awaited, as before: a slow or
  /// failing Firebase call must not hold a partner on the OTP screen. Its
  /// failure is swallowed here because there is nothing the login can do
  /// about it, and the push service retries on the next token refresh.
  Future<void> save(Map<String, dynamic> response) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(tokenKey, response['token'] ?? '');
    await prefs.setString(roleKey, response['role'] ?? '');
    await prefs.setString(stateKey, jsonEncode(response));

    _registerPush().catchError((Object _) {});
  }

  /// Whether the saved login has expired (logins last 90 days).
  ///
  /// Only a 401 counts: offline, slow or any other answer keeps the partner
  /// signed in, as before. An expired login is cleared the same way the
  /// logout button clears it.
  static Future<bool> clearIfExpired({
    Duration timeout = const Duration(seconds: 4),
    Future<int> Function()? probe,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(tokenKey);
    if (token == null || token.isEmpty) return false;

    int status;
    try {
      status = await (probe ?? _probe)().timeout(timeout);
    } catch (_) {
      return false;
    }
    if (status != 401) return false;

    await prefs.clear();
    return true;
  }

  static Future<int> _probe() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/partner/auth/check'),
      headers: await ApiConfig.headers(),
    );
    return response.statusCode;
  }
}
