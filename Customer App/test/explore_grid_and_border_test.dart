import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/screens/tabs/explore_tab.dart';
import 'package:customer_app/services/http_client.dart' as api;
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/widgets/discovery_salon_card.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost/api');
  });

  group('Salon Card Borders', () {
    testWidgets('DiscoverySalonCard has 1.0px border', (tester) async {
      final sampleSalon = {
        'id': 's1',
        'name': 'Glow Lounge',
        'address': '123 Main St',
        'avg_rating': 4.8,
        'review_count': 12,
        'is_serviceable': true,
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DiscoverySalonCard(
              salon: sampleSalon,
              onToggleFavourite: () {},
            ),
          ),
        ),
      );

      final containerFinder = find.byType(Container);
      expect(containerFinder, findsWidgets);

      bool foundCardWith1pxBorder = false;
      for (final element in containerFinder.evaluate()) {
        final widget = element.widget as Container;
        if (widget.decoration is BoxDecoration) {
          final box = widget.decoration as BoxDecoration;
          if (box.border != null && box.border is Border) {
            final border = box.border as Border;
            if (border.top.width == 1.0) {
              foundCardWith1pxBorder = true;
              break;
            }
          }
        }
      }
      expect(foundCardWith1pxBorder, isTrue);
    });
  });

  group('ExploreTab Grid View & Repositioned Count', () {
    final salonsJson = jsonEncode({
      'salons': [
        {
          'id': 1,
          'name': 'Salon Luxe',
          'address': 'MG Road',
          'avg_rating': 4.9,
          'review_count': 25,
          'cover_image': '',
          'is_serviceable': true,
        },
        {
          'id': 2,
          'name': 'Style Studio',
          'address': 'Brigade Road',
          'avg_rating': 4.6,
          'review_count': 10,
          'cover_image': '',
          'is_serviceable': true,
        },
      ],
      'suggested_salons': [],
      'suggested_city': null,
    });

    setUp(() {
      api.debugSetClient(
        MockClient((request) async {
          final path = request.url.path;
          if (path.contains('/customer/salons')) {
            return http.Response(
              salonsJson,
              200,
              headers: {'content-type': 'application/json'},
            );
          } else if (path.contains('/appointments/my-bookings')) {
            return http.Response(
              jsonEncode({'upcoming': [], 'past': []}),
              200,
              headers: {'content-type': 'application/json'},
            );
          } else if (path.contains('/cart')) {
            return http.Response(
              jsonEncode({
                'items': [],
                'summary': {'item_count': 0},
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            '{}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
    });

    testWidgets('toggles between List View and Grid View properly', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: ExploreTab()),
        ),
      );

      // Pump multiple frames for async load
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // View toggle icons exist
      final listIconFinder = find.byIcon(Icons.format_list_bulleted_rounded);
      final gridIconFinder = find.byIcon(Icons.grid_view_rounded);

      expect(listIconFinder, findsOneWidget);
      expect(gridIconFinder, findsOneWidget);

      // Initially in List View (GridView is not in All Salons)
      expect(find.byType(GridView), findsNothing);

      // Tap Grid View icon
      await tester.tap(gridIconFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // GridView is now rendered!
      expect(find.byType(GridView), findsOneWidget);

      // Both salons are present in Grid View
      expect(find.text('Salon Luxe'), findsWidgets);
      expect(find.text('Style Studio'), findsWidgets);

      // Tap back to List View
      await tester.tap(listIconFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Back to List View
      expect(find.byType(GridView), findsNothing);
      expect(find.text('Salon Luxe'), findsWidgets);
      expect(find.text('Style Studio'), findsWidgets);
    });

    testWidgets(
      'salon count badge is removed from besides All Salons near you',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: ExploreTab()),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 300));

        // Title is rendered cleanly without count badge
        expect(find.text('All Salons near you'), findsOneWidget);

        // Verify that the header Row contains only the title and the view toggle
        final headerFinder = find.ancestor(
          of: find.text('All Salons near you'),
          matching: find.byType(Row),
        );
        expect(headerFinder, findsWidgets);
      },
    );

    testWidgets(
      'salon cards in List View have foregroundDecoration border and antiAlias clipping',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: ExploreTab()),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 300));

        // Find containers with antiAlias clipping and foregroundDecoration
        final containers = tester.widgetList<Container>(find.byType(Container));
        bool foundCardWithProperBorder = false;

        for (final container in containers) {
          if (container.clipBehavior == Clip.antiAlias &&
              container.foregroundDecoration is BoxDecoration) {
            final fg = container.foregroundDecoration as BoxDecoration;
            if (fg.border != null && fg.borderRadius != null) {
              foundCardWithProperBorder = true;
              break;
            }
          }
        }

        expect(foundCardWithProperBorder, isTrue);
      },
    );
  });
}
