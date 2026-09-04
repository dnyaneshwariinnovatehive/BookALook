import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/dashboard/more/upgrade_plan_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const PartnerApp());
}

class PartnerApp extends StatelessWidget {
  const PartnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BookALook Partner',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: const SplashScreen(),
      routes: {
        '/upgrade_plan': (context) => const UpgradePlanScreen(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
