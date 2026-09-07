import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io' show Platform;

/// The single source of truth for the API host.
///
/// Every service must go through [baseUrl]. Reading `API_BASE_URL` from dotenv
/// directly is what let the appointments service drift onto a different host
/// from the rest of the app, so writes and reads could land on different
/// backends.
class ApiConfig {
  // Used for physical device testing when .env does not set API_BASE_URL.
  static const String _physicalDeviceIp = '192.168.41.204';

  static String get baseUrl {
    // An explicit .env value always wins, so a build can be pointed at
    // staging or a different machine without touching code.
    final configured = dotenv.env['API_BASE_URL'];
    if (configured != null && configured.trim().isNotEmpty) {
      return configured.trim();
    }

    if (kIsWeb) {
      // Chrome/Web testing
      return 'http://localhost:8000/api';
    } else if (Platform.isAndroid) {
      // Android Emulator uses 10.0.2.2 to point to host's localhost.
      // A physical device needs the machine's network IP instead.
      return 'http://$_physicalDeviceIp:8000/api';
    } else if (Platform.isIOS) {
      // iOS Simulator
      return 'http://localhost:8000/api';
    }
    return 'http://localhost:8000/api';
  }
}
