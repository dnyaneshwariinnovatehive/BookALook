import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/screens/dashboard/tabs/more_tab.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'isDarkMode': false,
      'auth_token': 'mock-token',
      'auth_state':
          '{"user":{"name":"Owner Rajesh","phone":"+91 9876543210"},"role":"admin"}',
    });
  });

  Widget createWidgetUnderTest({
    Map<String, dynamic>? salonData,
    Function(Map<String, dynamic>)? onSalonUpdated,
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(size: Size(500, 1000)),
          child: MoreTab(
            salonData:
                salonData ??
                {
                  'id': 'salon-101',
                  'name': 'Glitz Salon',
                  'city': {'name': 'Mumbai'},
                  'cover_photo_url': null,
                  'admin': {'name': 'Rajesh Admin', 'phone': '+91 9876543210'},
                },
            planName: 'Growth',
            daysRemaining: 45,
            onSalonUpdated: onSalonUpdated,
          ),
        ),
      ),
    );
  }

  group('MoreTab Search & Navigation Widget Tests', () {
    testWidgets('1. Search field is rendered at top with placeholder', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search settings and features'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
    });

    testWidgets('2. Normal More menu is displayed when query is empty', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      expect(find.text('Glitz Salon'), findsOneWidget);
      expect(find.text('Salon Location'), findsOneWidget);
      expect(find.text('Change Salon Timings'), findsOneWidget);

      // Scroll down in the ListView to reveal remaining section items
      await tester.drag(find.byType(ListView), const Offset(0, -250));
      await tester.pump();

      expect(find.text('Offers & Discounts'), findsOneWidget);
    });

    testWidgets(
      '3. Typing a query temporarily replaces menu with ranked search results',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pump();

        // Enter query "timings"
        await tester.enterText(find.byType(TextField), 'timings');
        await tester.pump();

        // Normal salon card should be hidden
        expect(find.text('Glitz Salon'), findsNothing);

        // Search results should display Change Salon Timings
        expect(find.text('Change Salon Timings'), findsOneWidget);
        expect(find.text('SALON MANAGEMENT'), findsOneWidget);
      },
    );

    testWidgets(
      '4. Tapping clear button empties query and restores normal More menu',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'timings');
        await tester.pump();
        expect(find.text('Glitz Salon'), findsNothing);

        // Tap clear icon
        final clearFinder = find.byIcon(Icons.cancel_rounded);
        expect(clearFinder, findsOneWidget);
        await tester.tap(clearFinder);
        await tester.pump();

        // Normal menu restored
        expect(find.text('Glitz Salon'), findsOneWidget);
        expect(find.text('Salon Location'), findsOneWidget);
      },
    );

    testWidgets(
      '5. Natural search query "working hours" finds Change Salon Timings',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'working hours');
        await tester.pump();

        expect(find.text('Change Salon Timings'), findsOneWidget);
      },
    );

    testWidgets('6. Searching "salary" or "payslip" finds Staff Payroll', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'salary');
      await tester.pump();

      expect(find.text('Staff Payroll'), findsOneWidget);
    });

    testWidgets('7. Searching "whatsapp" finds Automated Messaging', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'whatsapp');
      await tester.pump();

      expect(find.text('Automated Messaging'), findsOneWidget);
    });

    testWidgets(
      '8. No-results state displays empty illustration and suggestion chips',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'nonexistentfeature');
        await tester.pump();

        expect(
          find.text('No settings found for "nonexistentfeature"'),
          findsOneWidget,
        );
        expect(find.text('POPULAR SEARCHES'), findsOneWidget);
        expect(find.text('Offers'), findsOneWidget);

        // Tap "Offers" chip
        await tester.tap(find.text('Offers'));
        await tester.pump();

        expect(find.text('Offers & Discounts'), findsOneWidget);
      },
    );

    testWidgets('9. Searching "dark mode" renders the live inline switch', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'dark mode');
      await tester.pump();

      expect(find.text('Dark Mode'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    });
  });
}
