import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

class ApiConfig {
  // Replace this with your computer's actual local IPv4 address for physical device testing
  static const String _physicalDeviceIp = '192.168.41.204';
  
  static String get baseUrl {
    if (kIsWeb) {
      // Chrome/Web testing
      return 'http://localhost:8000/api';
    } else if (Platform.isAndroid) {
      // Android Emulator uses 10.0.2.2 to point to host's localhost
      // If you are using a physical device via USB, it needs the network IP
      // We assume physical device if it's not the emulator IP, but for safety:
      return 'http://$_physicalDeviceIp:8000/api'; 
      // Change to 'http://10.0.2.2:8000/api' if testing on Android Emulator
    } else if (Platform.isIOS) {
      // iOS Simulator
      return 'http://localhost:8000/api';
    }
    return 'http://localhost:8000/api';
  }
}
