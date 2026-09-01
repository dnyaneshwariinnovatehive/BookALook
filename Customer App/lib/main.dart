import 'package:flutter/material.dart';
import 'services/auth_service.dart';
import 'screens/phone_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Check if user is already logged in
  final token = await AuthService.getToken();
  
  runApp(MyApp(initialToken: token));
}

class MyApp extends StatelessWidget {
  final String? initialToken;

  const MyApp({Key? key, this.initialToken}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BookALook Customer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      // If token exists, go straight to Home, else go to Auth
      home: initialToken != null ? HomeScreen() : PhoneScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
