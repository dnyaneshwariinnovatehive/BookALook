import 'dart:convert';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../firebase_options.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'deep_link_service.dart';
import '../screens/salon_detail_screen.dart';

// Top-level function for background message handling
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("Handling a background message: ${message.messageId}");
}

class PushNotificationService {
  final String baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api';
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  Future<void> init() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      debugPrint("Firebase initialization failed (expected if missing credentials): $e");
      // Continue anyway; we don't want to crash the app if FCM isn't configured yet.
    }

    try {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Local notifications for foreground
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);
      await _localNotifications.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Request permission
      NotificationSettings settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('User granted permission');
      }

      // Foreground message listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Received a foreground message: ${message.messageId}');
        _showLocalNotification(message);
      });

      // App opened from background state listener
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('Message clicked from background!');
        _handleRouting(message.data);
      });

      // App opened from terminated state
      RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('Message clicked from terminated state!');
        _handleRouting(initialMessage.data);
      }

      // Register device on backend
      await registerDevice();

      // Listen for token refreshes
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _sendTokenToBackend(newToken);
      });
    } catch (e) {
      debugPrint("FCM setup failed: $e");
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'bookalook_customer_channel', // id
        'Customer Notifications', // title
        importance: Importance.max,
        priority: Priority.high,
      );
      const NotificationDetails platformDetails =
          NotificationDetails(android: androidDetails);

      await _localNotifications.show(
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: platformDetails,
        payload: jsonEncode(message.data),
      );
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!);
        _handleRouting(data);
      } catch (e) {
        debugPrint('Error parsing notification payload: $e');
      }
    }
  }

  void _handleRouting(Map<String, dynamic> data) {
    debugPrint('Routing to based on data: $data');
    final String? action = data['action'];
    final String? entityType = data['entity_type'];
    final String? entityId = data['entity_id'];
    
    final navigator = DeepLinkService.navigatorKey.currentState;
    if (navigator == null) return;
    
    // Example: Navigate to Salon
    if (entityType == 'salon' && entityId != null) {
      navigator.push(
        MaterialPageRoute(builder: (_) => SalonDetailScreen(salonId: entityId)),
      );
    }
    // E.g. Navigate to appointment details if entityType == 'appointment'
    // Currently no AppointmentDetailScreen imported, so just leaving foundation
  }

  Future<void> registerDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) return; // Not authenticated

    try {
      String? fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await _sendTokenToBackend(fcmToken);
      }
    } catch (e) {
      debugPrint("Error registering device: $e");
    }
  }

  Future<void> _sendTokenToBackend(String fcmToken) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) return;

    try {
      String platform = 'android';
      if (!kIsWeb && Platform.isIOS) platform = 'ios';

      await http.post(
        Uri.parse('$baseUrl/customer/devices/register'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'app_type': 'customer_app',
          'platform': platform,
          'push_token': fcmToken,
          'app_version': '1.0.0', // Ideally from package_info_plus
          'device_model': 'Unknown', // Ideally from device_info_plus
          'os_version': 'Unknown',
        }),
      );
      debugPrint("FCM token registered with backend");
    } catch (e) {
      debugPrint("Failed to send token to backend: $e");
    }
  }

  Future<void> unregisterDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) return;

    try {
      String? fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await http.post(
          Uri.parse('$baseUrl/customer/devices/unregister'),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'push_token': fcmToken,
          }),
        );
        debugPrint("FCM token unregistered from backend");
      }
    } catch (e) {
      debugPrint("Error unregistering device: $e");
    }
  }
}
