import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:partner_app/models/onboarding_draft.dart';
import 'package:partner_app/screens/collaborator/service_picker_sheet.dart';
import 'package:partner_app/services/salon_location_api.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/widgets/device_location_prompt.dart';

final catalog = [
  {
    'id': 'cat-1',
    'name': 'Hair Styling',
    'templates': [
      {'id': 't-1', 'name': 'Classic Haircut', 'estimated_duration_minutes': 30},
      {'id': 't-2', 'name': 'Beard Grooming', 'estimated_duration_minutes': 20},
    ],
  },
];

Position _pos(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime(2026),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  group('pricing a service inline', () {
    late List<DraftService> saved;

    Widget sheet({Set<String> existing = const {}}) => MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: ServicePickerSheet(
              initialCategories: catalog,
              existingTemplateIds: existing,
              onSave: (s) async {
                saved.removeWhere((x) => x.templateId == s.templateId);
                saved.add(s);
                return null;
              },
              onRemove: (id) async => saved.removeWhere((x) => x.templateId == id),
              priceOf: (id) => saved.where((x) => x.templateId == id).firstOrNull?.price,
            ),
          ),
        );

    setUp(() => saved = []);

    testWidgets('tapping a service opens a price box in the list, not a new page', (tester) async {
      await tester.pumpWidget(sheet());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Beard Grooming'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('inline-price-field')), findsOneWidget);
      expect(find.text('Add to the menu'), findsNothing, reason: 'no separate price page');
      expect(find.text('Classic Haircut'), findsOneWidget, reason: 'the list stays on screen');
    });

    testWidgets('Add saves straight away and the line is tagged Added', (tester) async {
      await tester.pumpWidget(sheet());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Beard Grooming'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('inline-price-field')), '150');
      await tester.tap(find.byKey(const ValueKey('inline-price-save')));
      await tester.pumpAndSettle();

      expect(saved.single.templateId, 't-2');
      expect(saved.single.price, 150);
      expect(find.text('Added'), findsOneWidget);
      expect(find.text('1 added'), findsOneWidget, reason: 'the category count follows too');
      expect(find.byKey(const ValueKey('inline-price-field')), findsNothing, reason: 'box closes');
      expect(find.byType(ServicePickerSheet), findsOneWidget, reason: 'sheet stays open for the next');
    });

    testWidgets('an empty price is refused', (tester) async {
      await tester.pumpWidget(sheet());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Classic Haircut'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('inline-price-save')));
      await tester.pump();

      expect(saved, isEmpty);
      expect(find.text('Enter a price.'), findsOneWidget);
    });

    testWidgets('an Added line can be re-priced or removed in place', (tester) async {
      saved = [DraftService(templateId: 't-1', name: 'Classic Haircut', categoryName: 'Hair Styling', durationMinutes: 30, price: 200)];
      await tester.pumpWidget(sheet(existing: {'t-1'}));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Classic Haircut'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byKey(const ValueKey('inline-price-field')));
      expect(field.controller!.text, '200', reason: 'starts from the saved price');
      expect(find.text('Update'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('inline-price-field')), '250');
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(saved.single.price, 250);
      expect(find.text('Added'), findsOneWidget);

      await tester.tap(find.text('Classic Haircut'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from menu'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(find.text('Added'), findsNothing);
    });
  });

  group('use this location with GPS off', () {
    Future<Position?> run(
      WidgetTester tester, {
      required List<Object> reads,
      required bool gpsOnAfter,
      bool tapGo = true,
      List<String>? messages,
      List<String>? opened,
    }) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(builder: (c) {
          ctx = c;
          return const Scaffold();
        }),
      ));

      var i = 0;
      final future = captureDevicePosition(
        ctx,
        onMessage: (m) => messages?.add(m),
        readPosition: () async {
          final r = reads[i++];
          if (r is Position) return r;
          throw r;
        },
        isGpsOn: () async => gpsOnAfter,
        openLocationSettings: () async => opened?.add('location'),
        openAppSettings: () async => opened?.add('app'),
        waitForReturn: () async {},
      );
      await tester.pumpAndSettle();

      if (find.byKey(const ValueKey('location-prompt-go')).evaluate().isNotEmpty) {
        await tester.tap(tapGo ? find.byKey(const ValueKey('location-prompt-go')) : find.text('Not now'));
        await tester.pumpAndSettle();
      }
      return future;
    }

    testWidgets('asks to turn GPS on, opens settings, then pins on return', (tester) async {
      final opened = <String>[];
      final position = await run(
        tester,
        reads: [LocationDisabledException(), _pos(18.5, 73.8)],
        gpsOnAfter: true,
        opened: opened,
      );

      expect(opened, ['location']);
      expect(position?.latitude, 18.5);
    });

    testWidgets('says so when GPS is still off after returning', (tester) async {
      final messages = <String>[];
      final position = await run(
        tester,
        reads: [LocationDisabledException()],
        gpsOnAfter: false,
        messages: messages,
      );

      expect(position, isNull);
      expect(messages.single, contains('still off'));
    });

    testWidgets('Not now leaves it for later without opening anything', (tester) async {
      final opened = <String>[];
      final messages = <String>[];
      final position = await run(
        tester,
        reads: [LocationDisabledException()],
        gpsOnAfter: false,
        tapGo: false,
        opened: opened,
        messages: messages,
      );

      expect(position, isNull);
      expect(opened, isEmpty);
      expect(messages.single, contains('pin the salon later'));
    });

    testWidgets('permission blocked for good goes through app settings', (tester) async {
      final opened = <String>[];
      final position = await run(
        tester,
        reads: [LocationPermissionPermanentlyDeniedException(), _pos(19.0, 72.8)],
        gpsOnAfter: true,
        opened: opened,
      );

      expect(opened, ['app']);
      expect(position?.latitude, 19.0);
    });
  });
}
