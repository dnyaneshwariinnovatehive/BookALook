import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:customer_app/screens/categories_screen.dart';
import 'package:customer_app/services/app_version_service.dart';
import 'package:customer_app/services/http_client.dart' as api;
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/utils/bottom_clearance.dart';

void main() {
  late Completer<void> gate;
  late String responseJson;

  String generateCategoriesJson(List<String> names) {
    final list = names
        .map((n) => '{"id":"cat-${n.toLowerCase()}","name":"$n","icon_url":"https://api.bookalook.in/icons/$n.png"}')
        .join(',');
    return '{"categories":[$list]}';
  }

  setUp(() {
    gate = Completer<void>()..complete();
    responseJson = generateCategoriesJson(['Hair', 'Skin', 'Nails', 'Spa', 'Grooming']);
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost/api');
    AppVersionService.instance.debugVersion = '1.5.0';
    AppVersionService.instance.debugBuildNumber = 10;
    api.debugSetClient(MockClient((request) async {
      await gate.future;
      return http.Response(responseJson, 200);
    }));
  });

  tearDown(() {
    AppVersionService.instance.debugVersion = null;
    AppVersionService.instance.debugBuildNumber = null;
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    EdgeInsets padding = const EdgeInsets.only(top: 44, bottom: 34),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = FakeViewPadding(
      top: padding.top,
      bottom: padding.bottom,
      left: padding.left,
      right: padding.right,
    );
    addTearDown(tester.view.reset);

    gate = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const CategoriesScreen(),
      ),
    );
    await tester.pump();
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('Explore Categories - Compact Height & Dynamic Grid UI', () {
    testWidgets('cards have childAspectRatio of 1.01 (~8.9% height reduction vs 0.92)', (tester) async {
      await pumpScreen(tester);

      final gridFinder = find.byType(GridView);
      expect(gridFinder, findsOneWidget);

      final gridView = tester.widget<GridView>(gridFinder);
      final delegate = gridView.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;

      expect(delegate.crossAxisCount, equals(2));
      expect(delegate.childAspectRatio, equals(1.01));

      // Math verification:
      // Old aspect ratio = 0.92 -> height = width / 0.92 = 1.087 * width
      // New aspect ratio = 1.01 -> height = width / 1.01 = 0.990 * width
      // Height reduction = (1.086956 - 0.990099) / 1.086956 = 8.91%
      const oldRatio = 0.92;
      const newRatio = 1.01;
      final heightReduction = ( (1 / oldRatio) - (1 / newRatio) ) / (1 / oldRatio);
      expect(heightReduction, greaterThanOrEqualTo(0.08));
      expect(heightReduction, lessThanOrEqualTo(0.10));
    });

    testWidgets('all category cards have equal dimensions in the two-column grid', (tester) async {
      await pumpScreen(tester);

      final comboRect = tester.getRect(find.ancestor(of: find.text('Combo'), matching: find.byType(InkWell)).first);
      final hairRect = tester.getRect(find.ancestor(of: find.text('Hair'), matching: find.byType(InkWell)).first);

      expect(comboRect.height, moreOrLessEquals(hairRect.height, epsilon: 0.1));
      expect(comboRect.width, moreOrLessEquals(hairRect.width, epsilon: 0.1));
    });

    testWidgets('fully dynamic: automatically creates rows when Superadmin adds categories', (tester) async {
      // 11 Superadmin categories + Combo = 12 total cards across 6 rows
      responseJson = generateCategoriesJson([
        'Hair', 'Skin', 'Nails', 'Spa', 'Grooming',
        'Facial', 'Massage', 'Makeup', 'Bridal', 'Tattoo', 'Piercing'
      ]);

      await pumpScreen(tester);

      // Verify that Combo and the first few categories are rendered
      expect(find.text('Combo'), findsOneWidget);
      expect(find.text('Hair'), findsOneWidget);
      expect(find.text('Skin'), findsOneWidget);
      expect(find.text('Nails'), findsOneWidget);

      // Scroll down to reveal subsequent rows generated dynamically
      await tester.drag(find.byType(GridView), const Offset(0, -600));
      await tester.pump();

      expect(find.text('Piercing'), findsOneWidget);
      expect(find.text('Tattoo'), findsOneWidget);

      // Verify no empty placeholder cards exist
      expect(tester.takeException(), isNull);
    });

    testWidgets('fully dynamic: adapts without placeholder cards when categories are few', (tester) async {
      // Only 2 categories + Combo = 3 total cards
      responseJson = generateCategoriesJson(['Hair', 'Skin']);

      await pumpScreen(tester);

      expect(find.text('Combo'), findsOneWidget);
      expect(find.text('Hair'), findsOneWidget);
      expect(find.text('Skin'), findsOneWidget);
      expect(find.text('Nails'), findsNothing);

      // Exactly 3 InkWell cards (one per category item)
      final inkWells = find.descendant(of: find.byType(GridView), matching: find.byType(InkWell));
      expect(inkWells, findsNWidgets(3));
    });

    testWidgets('grid has sufficient bottom clearance above bottom navigation bar and safe area', (tester) async {
      const bottomInset = 34.0;
      await pumpScreen(tester, padding: const EdgeInsets.only(top: 44, bottom: bottomInset));

      final gridView = tester.widget<GridView>(find.byType(GridView));
      final padding = gridView.padding as EdgeInsets;

      // Expect bottom padding to be at least bottomInset + 32
      expect(padding.bottom, greaterThanOrEqualTo(bottomInset + 32));
    });

    testWidgets('search functionality filters dynamic categories accurately', (tester) async {
      responseJson = generateCategoriesJson(['Hair Care', 'Skin Therapy', 'Nails & Art', 'Spa Wellness']);
      await pumpScreen(tester);

      expect(find.text('Hair Care'), findsOneWidget);
      expect(find.text('Skin Therapy'), findsOneWidget);

      // Enter search query
      await tester.enterText(find.byType(TextField), 'Skin');
      await tester.pump();

      expect(find.text('Skin Therapy'), findsOneWidget);
      expect(find.text('Hair Care'), findsNothing);
      expect(find.text('Combo'), findsNothing);

      // Clear search
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();

      expect(find.text('Hair Care'), findsOneWidget);
      expect(find.text('Skin Therapy'), findsOneWidget);
      expect(find.text('Combo'), findsOneWidget);
    });

    testWidgets('renders without overflow on narrow 320px mobile screens', (tester) async {
      responseJson = generateCategoriesJson(['Hair Styling & Extensions', 'Skin Rejuvenation Treatment', 'Nail Art Studio']);
      await pumpScreen(tester, size: const Size(320, 568), padding: const EdgeInsets.only(top: 20, bottom: 20));

      expect(tester.takeException(), isNull);
      expect(find.text('Combo'), findsOneWidget);
    });

    testWidgets('renders without overflow on modern 390px and 412px mobile screens', (tester) async {
      await pumpScreen(tester, size: const Size(390, 844));
      expect(tester.takeException(), isNull);

      await pumpScreen(tester, size: const Size(412, 915));
      expect(tester.takeException(), isNull);
    });
  });
}
