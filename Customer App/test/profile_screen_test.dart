import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/screens/profile_screen.dart';
import 'package:customer_app/services/http_client.dart' as api;
import 'package:customer_app/theme/app_theme.dart';

/// The sign-up form reports every problem next to its field, not in a
/// SnackBar — this screen has the keyboard up most of the time.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost/api');
    // The city picker asks for cities on mount; an empty list is enough here.
    api.debugSetClient(MockClient((_) async => http.Response('[]', 200)));
  });

  Future<void> pumpForm(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: const ProfileScreen(phone: '9876543210'),
    ));
    await tester.pump();
  }

  Future<void> acceptTermsAndSubmit(WidgetTester tester) async {
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    final submit = find.text('Complete & Login');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
  }

  testWidgets('submitting an empty form marks every missing field at once', (tester) async {
    await pumpForm(tester);
    await acceptTermsAndSubmit(tester);

    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Name is required'), findsOneWidget);
    expect(find.text('Date of Birth is required'), findsOneWidget);
    expect(find.byKey(ProfileScreen.locationErrorKey), findsOneWidget);
    expect(find.text('Please choose your city'), findsOneWidget);
  });

  testWidgets('typing a name clears only the name error', (tester) async {
    await pumpForm(tester);
    await acceptTermsAndSubmit(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Full Name *'), 'Asha');
    await tester.pump();

    expect(find.text('Name is required'), findsNothing);
    expect(find.text('Date of Birth is required'), findsOneWidget);
  });

  testWidgets('the submit button stays disabled until the terms are accepted', (tester) async {
    await pumpForm(tester);

    final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Complete & Login'));
    expect(button.onPressed, isNull);
  });
}
