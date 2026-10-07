import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:customer_app/services/location_service.dart';
import 'package:customer_app/widgets/location_permission_modal.dart';
import 'package:customer_app/theme/app_theme.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('LocationPermissionModal renders all approved content correctly',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showLocationPermissionModal(context),
              child: const Text('Show Modal'),
            ),
          ),
        ),
      ),
    );

    // Tap to open modal
    await tester.tap(find.text('Show Modal'));
    await tester.pumpAndSettle();

    // Verify Heading and Subtitle
    expect(find.text('Turn on your location'), findsOneWidget);
    expect(
      find.text(
          'Discover salons near you and get a more\npersonalized BookALook experience.'),
      findsOneWidget,
    );

    // Verify 3 Benefits
    expect(find.text('Discover salons near you'), findsOneWidget);
    expect(
      find.text('Find salons and services available around your location.'),
      findsOneWidget,
    );

    expect(find.text('Better recommendations'), findsOneWidget);
    expect(
      find.text('See relevant salons, services and availability nearby.'),
      findsOneWidget,
    );

    expect(find.text('Plan your visit easily'), findsOneWidget);
    expect(
      find.text('Get more accurate location-based salon information.'),
      findsOneWidget,
    );

    // Verify CTAs
    expect(find.text('Enable location'), findsOneWidget);
    expect(find.text('Select location manually'), findsOneWidget);
    expect(
      find.text('You can change this anytime in Settings.'),
      findsOneWidget,
    );

    // Verify Close button exists and dismisses modal
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Turn on your location'), findsNothing);
  });

  testWidgets('LocationService prompt tracking works correctly', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final service = LocationService.instance;
    expect(await service.hasPromptedInitialLocation(), isFalse);

    await service.markInitialLocationPrompted();
    expect(await service.hasPromptedInitialLocation(), isTrue);

    expect(service.canShowPostLoginReminder, isTrue);
    service.markPostLoginReminded();
    expect(service.canShowPostLoginReminder, isFalse);
  });
}
