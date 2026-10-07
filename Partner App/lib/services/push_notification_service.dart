import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'api_config.dart';
import '../main.dart' as main;
import 'package:path_provider/path_provider.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("Handling a background message: ${message.messageId}");
}

class PushNotificationService {
  final String baseUrl = ApiConfig.baseUrl;
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
    }

    try {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);
      await _localNotifications.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      NotificationSettings settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('User granted permission');
      }

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Received a foreground message: ${message.messageId}');
        _showLocalNotification(message);
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('Message clicked from background!');
        _handleRouting(message.data);
      });

      RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('Message clicked from terminated state!');
        _handleRouting(initialMessage.data);
      }

      await registerDevice();

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _sendTokenToBackend(newToken);
      });
    } catch (e) {
      debugPrint("FCM setup failed: $e");
    }
  }

  Future<String?> _downloadAndSaveImage(String url, String fileName) async {
    try {
      final Directory directory = await getTemporaryDirectory();
      final String filePath = '${directory.path}/$fileName';
      final http.Response response = await http.get(Uri.parse(url));
      final File file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      return filePath;
    } catch (e) {
      debugPrint('Error downloading push image: $e');
      return null;
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      StyleInformation? styleInformation;
      String? imageUrl = android.imageUrl;
      
      // Fallback if not mapped directly
      if (imageUrl == null && message.data.containsKey('push_image_url')) {
        imageUrl = message.data['push_image_url'];
      }

      if (imageUrl != null && imageUrl.isNotEmpty) {
        // Must use https to avoid cleartext HTTP issues on Android 9+
        if (imageUrl.startsWith('http://localhost') || imageUrl.startsWith('http://127.0.0.1')) {
           debugPrint('Cannot download localhost image on device: $imageUrl');
        } else {
           final String? downloadedPath = await _downloadAndSaveImage(imageUrl, 'push_image_${notification.hashCode}.png');
           if (downloadedPath != null) {
             styleInformation = BigPictureStyleInformation(
               FilePathAndroidBitmap(downloadedPath),
               hideExpandedLargeIcon: true,
             );
           }
        }
      }

      AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'bookalook_partner_channel',
        'Partner Notifications',
        importance: Importance.max,
        priority: Priority.high,
        styleInformation: styleInformation,
      );
      NotificationDetails platformDetails =
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
    if (data.containsKey('type')) {
      final String type = data['type'];
      // Wait for navigator to be ready
      Future.delayed(const Duration(milliseconds: 500), () {
        final context = main.navigatorKey.currentContext;
        if (context != null) {
          // Typically we would parse an appointment_id and navigate to details.
          // For now, simply log and show a snackbar as foundation
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(duration: const Duration(milliseconds: 2500), content: Text('Received notification type: $type')),
          );
        }
      });
    }
  }

  Future<void> registerDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) return;

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
        Uri.parse('$baseUrl/partner/devices/register'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'app_type': 'partner_app',
          'platform': platform,
          'push_token': fcmToken,
          'app_version': '1.0.0',
          'device_model': 'Unknown',
          'os_version': 'Unknown',
        }),
      );
      debugPrint("FCM token registered with backend (Partner App)");
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
          Uri.parse('$baseUrl/partner/devices/unregister'),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'push_token': fcmToken,
          }),
        );
        debugPrint("FCM token unregistered from backend (Partner App)");
      }
    } catch (e) {
      debugPrint("Error unregistering device: $e");
    }
  }
}
