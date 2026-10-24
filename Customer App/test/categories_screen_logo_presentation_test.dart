import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:customer_app/models/category.dart';
import 'package:customer_app/screens/categories_screen.dart';
import 'package:customer_app/services/app_version_service.dart';
import 'package:customer_app/services/http_client.dart' as api;
import 'package:customer_app/theme/app_theme.dart';

const _sampleCategoriesJson = '''
{
  "categories": [
    {
      "id": "cat-hair",
      "name": "Hair",
      "icon_url": "https://api.bookalook.in/storage/category_icons/hair-logo.png"
    },
    {
      "id": "cat-skin",
      "name": "Skin",
      "icon_url": "https://api.bookalook.in/storage/category_icons/skin-logo.png"
    },
    {
      "id": "cat-nails",
      "name": "Nails",
      "icon_url": "https://api.bookalook.in/storage/category_icons/nails-logo.png"
    },
    {
      "id": "cat-spa",
      "name": "Spa",
      "icon_url": "https://api.bookalook.in/storage/category_icons/spa-logo.png"
    },
    {
      "id": "cat-grooming",
      "name": "Grooming",
      "icon_url": "https://api.bookalook.in/storage/category_icons/grooming-logo.png"
    }
  ]
}
''';

void main() {
  late Completer<void> gate;

  setUp(() {
    gate = Completer<void>()..complete();
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost/api');
    AppVersionService.instance.debugVersion = '1.5.0';
    AppVersionService.instance.debugBuildNumber = 10;
    api.debugSetClient(MockClient((request) async {
      await gate.future;
      return http.Response(_sampleCategoriesJson, 200);
    }));
  });

  tearDown(() {
    AppVersionService.instance.debugVersion = null;
    AppVersionService.instance.debugBuildNumber = null;
  });

  Future<void> pumpCategories(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
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

  group('Explore Categories - Logo Presentation Redesign', () {
    testWidgets('dynamic Superadmin logo URLs are rendered via Image.network with contain fit and high quality', (tester) async {
      await pumpCategories(tester);

      // Verify category items are rendered
      expect(find.text('Hair'), findsOneWidget);
      expect(find.text('Skin'), findsOneWidget);
      expect(find.text('Combo'), findsOneWidget);

      // Find network images rendered for categories
      final networkImages = tester.widgetList<Image>(find.byType(Image)).where((img) => img.image is NetworkImage).toList();
      expect(networkImages.isNotEmpty, isTrue);

      final hairImg = networkImages.firstWhere(
        (img) => (img.image as NetworkImage).url == 'https://api.bookalook.in/storage/category_icons/hair-logo.png',
      );
      expect(hairImg.fit, equals(BoxFit.contain));
      expect(hairImg.alignment, equals(Alignment.center));
      expect(hairImg.filterQuality, equals(FilterQuality.high));
    });

    testWidgets('no white box or circular container wraps the category logo', (tester) async {
      await pumpCategories(tester);

      // In the old design, a 48x48 white container wrapped each logo:
      // Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white, ...))
      // Verify that no 48x48 white container exists in any category card.
      final containers = tester.widgetList<Container>(find.byType(Container));
      for (final container in containers) {
        if (container.constraints != null) {
          final is48x48 = container.constraints!.maxWidth == 48 && container.constraints!.maxHeight == 48;
          expect(is48x48, isFalse, reason: 'Found obsolete 48x48 icon container');
        }
      }
    });

    testWidgets('logo occupies the hero portion of the card and does not overlap text or arrow', (tester) async {
      await pumpCategories(tester);

      final hairTextFinder = find.text('Hair');
      expect(hairTextFinder, findsOneWidget);
      final hairCardCenter = tester.getCenter(hairTextFinder);

      // Find the Hair category network image
      final hairImgFinder = find.byWidgetPredicate(
        (w) => w is Image && w.image is NetworkImage && (w.image as NetworkImage).url.contains('hair-logo'),
      );
      expect(hairImgFinder, findsOneWidget);

      final imgRect = tester.getRect(hairImgFinder);
      final textRect = tester.getRect(hairTextFinder);

      // The logo must be positioned above the category name with clear separation
      expect(imgRect.bottom, lessThanOrEqualTo(textRect.top));

      // The logo must occupy substantial visual area (width and height >= 64px)
      expect(imgRect.height, greaterThanOrEqualTo(64));
      expect(imgRect.width, greaterThanOrEqualTo(64));
    });

    testWidgets('small circular arrow button is retained in top-right of the card', (tester) async {
      await pumpCategories(tester);

      // Find arrow icons on category cards
      final arrows = find.byIcon(Icons.arrow_forward_rounded);
      expect(arrows, findsWidgets);

      // Verify the arrow icon has size 14 and primary purple color
      final arrowWidget = tester.widget<Icon>(arrows.first);
      expect(arrowWidget.size, equals(14));
      expect(arrowWidget.color, equals(const Color(0xFF9850F1)));
    });

    testWidgets('all category cards have equal height and balanced aspect ratio', (tester) async {
      await pumpCategories(tester);

      // Find card ink wells or containers for Hair and Combo
      final comboRect = tester.getRect(find.ancestor(of: find.text('Combo'), matching: find.byType(InkWell)).first);
      final hairRect = tester.getRect(find.ancestor(of: find.text('Hair'), matching: find.byType(InkWell)).first);

      // Both cards must have exact equal height and equal width
      expect(comboRect.height, moreOrLessEquals(hairRect.height, epsilon: 0.1));
      expect(comboRect.width, moreOrLessEquals(hairRect.width, epsilon: 0.1));
      expect(comboRect.top, moreOrLessEquals(hairRect.top, epsilon: 0.1));
    });

    testWidgets('search functionality filters category list dynamically', (tester) async {
      await pumpCategories(tester);

      // Initially all categories visible
      expect(find.text('Hair'), findsOneWidget);
      expect(find.text('Skin'), findsOneWidget);

      // Enter search query
      await tester.enterText(find.byType(TextField), 'nai');
      await tester.pump();

      // Only Nails should be found
      expect(find.text('Nails'), findsOneWidget);
      expect(find.text('Hair'), findsNothing);
      expect(find.text('Skin'), findsNothing);

      // Clear search
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();

      expect(find.text('Hair'), findsOneWidget);
      expect(find.text('Skin'), findsOneWidget);
    });
  });
}
