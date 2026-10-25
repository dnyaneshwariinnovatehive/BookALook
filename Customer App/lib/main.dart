import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/splash_screen.dart';
import 'services/deep_link_service.dart';
import 'services/http_client.dart' show topRouteObserver;
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';

// Global notifier for theme mode, locked to light theme
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  
  // Clean up any legacy dark mode preference safely so light mode is permanently active
  final prefs = await SharedPreferences.getInstance();
  if (prefs.containsKey('isDark')) {
    await prefs.remove('isDark');
  }
  themeNotifier.value = ThemeMode.light;

  // Started before the first frame so a QR scan that launched the app is
  // already waiting to be routed rather than arriving too late to matter.
  await DeepLinkService.instance.start();

  // Initialize push notification foundation
  await PushNotificationService().init();

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // A link can land before any screen exists, so routing goes through
      // this key rather than a BuildContext.
      navigatorKey: DeepLinkService.navigatorKey,
      // Lets an expiring session see that the login page is already up.
      navigatorObservers: [topRouteObserver],
      title: 'BookALook Customer',
      theme: AppTheme.lightTheme,
      themeMode: ThemeMode.light,
      home: SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
