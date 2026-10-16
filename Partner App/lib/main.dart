import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/mandatory_update_screen.dart';
import 'services/api_config.dart' show mandatoryUpdateRouteName;
import 'services/app_version_service.dart';
import 'services/push_notification_service.dart';
import 'widgets/optional_update_dialog.dart';

// Global notifier for theme mode
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

// Global navigator key for routing from background/terminated states
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> _loadThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('isDarkMode') ?? false;
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await _loadThemeMode();
  await PushNotificationService().init();
  runApp(const PartnerApp());
}

class PartnerApp extends StatefulWidget {
  const PartnerApp({super.key});

  @override
  State<PartnerApp> createState() => _PartnerAppState();
}

class _PartnerAppState extends State<PartnerApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkVersionOnResume();
    }
  }

  Future<void> _checkVersionOnResume() async {
    try {
      final info = await AppVersionService.instance.checkUpdate();
      if (!mounted) return;
      final nav = navigatorKey.currentState;
      final ctx = navigatorKey.currentContext;

      if (info.isMandatory && nav != null && ctx != null) {
        nav.pushAndRemoveUntil(
          MaterialPageRoute(
            settings: const RouteSettings(name: mandatoryUpdateRouteName),
            builder: (_) => MandatoryUpdateScreen(updateInfo: info),
          ),
          (route) => false,
        );
      } else if (info.isOptional && ctx != null) {
        OptionalUpdateDialog.showIfEligible(ctx, info);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'BookALook Partner',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentMode,
          home: const SplashScreen(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
