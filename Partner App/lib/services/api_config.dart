import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_version_service.dart';
import '../screens/mandatory_update_screen.dart';
import '../main.dart' show navigatorKey;

/// Route name for the mandatory update screen.
const String mandatoryUpdateRouteName = 'mandatory-update';

/// The single source of truth for the API host and client configuration.
class ApiConfig {
  // Used for physical device testing when .env does not set API_BASE_URL.
  static const String _physicalDeviceIp = '192.168.41.204';

  static String get baseUrl {
    try {
      if (dotenv.isInitialized) {
        final configured = dotenv.env['API_BASE_URL'];
        if (configured != null && configured.trim().isNotEmpty) {
          return configured.trim();
        }
      }
    } catch (_) {}

    if (kIsWeb) {
      return 'http://localhost:8000/api';
    } else if (Platform.isAndroid) {
      return 'http://$_physicalDeviceIp:8000/api';
    } else if (Platform.isIOS) {
      return 'http://localhost:8000/api';
    }
    return 'http://localhost:8000/api';
  }

  /// Construct standard headers including auth token and version enforcement headers.
  static Future<Map<String, String>> headers({Map<String, String>? extra}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final base = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    try {
      final installed = await AppVersionService.instance.getInstalledVersion();
      base['X-App-Id'] = AppVersionService.appId;
      base['X-App-Version'] = installed['version'] as String;
      base['X-App-Build'] = (installed['build_number'] as int).toString();
    } catch (_) {}

    if (extra != null) {
      base.addAll(extra);
    }

    return base;
  }

  /// Intercept responses and route to MandatoryUpdateScreen if HTTP 426 Upgrade Required is returned.
  static Future<void> handleResponse(http.Response response) async {
    if (response.statusCode != 426) return;

    final navigator = navigatorKey.currentState;
    final context = navigatorKey.currentContext;
    if (navigator == null || context == null) return;

    Map<String, dynamic>? decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>?;
    } catch (_) {}

    final installed = await AppVersionService.instance.getInstalledVersion();
    final currentVer = installed['version'] as String;
    final currentBld = installed['build_number'] as int;

    final minVer = decoded?['minimum_version'] as String? ?? '2.0.0';
    final minBld = (decoded?['minimum_build'] as num?)?.toInt() ?? 1;
    final msg = decoded?['update_message'] as String? ?? decoded?['message'] as String?;
    final storeUrls = decoded?['store_urls'] as Map<String, dynamic>?;

    String? storeUrl;
    if (storeUrls != null) {
      try {
        storeUrl = Platform.isIOS ? storeUrls['ios'] as String? : storeUrls['android'] as String?;
      } catch (_) {
        storeUrl = storeUrls['android'] as String?;
      }
    }

    final info = AppUpdateInfo(
      type: UpdateType.mandatory,
      currentVersion: currentVer,
      currentBuild: currentBld,
      targetVersion: minVer,
      targetBuild: minBld,
      message: msg,
      storeUrl: storeUrl,
    );

    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: mandatoryUpdateRouteName),
        builder: (_) => MandatoryUpdateScreen(updateInfo: info),
      ),
      (route) => false,
    );
  }
}
