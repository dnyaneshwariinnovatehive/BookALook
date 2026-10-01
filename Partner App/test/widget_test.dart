import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:partner_app/main.dart';
import 'package:partner_app/screens/phone_screen.dart';

void main() {
  testWidgets('a fresh install goes from the splash to the phone screen',
      (WidgetTester tester) async {
    // No stored session. Without a mock the splash screen's SharedPreferences
    // call has no platform channel to talk to in a test.
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const PartnerApp());
    expect(find.byType(MaterialApp), findsOneWidget);

    // The splash holds for three seconds, then routes.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(PhoneScreen), findsOneWidget);
  });
}
