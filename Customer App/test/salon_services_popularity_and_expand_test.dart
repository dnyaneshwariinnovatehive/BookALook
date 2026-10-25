import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/screens/salon_detail_screen.dart';
import 'package:customer_app/services/http_client.dart' as api;
import 'package:customer_app/services/cart_service.dart';
import 'package:customer_app/theme/app_theme.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'auth_token': 'dummy_token'});
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost/api');
  });

  Map<String, dynamic> createSampleSalonWithServices({
    required List<Map<String, dynamic>> services,
    List<Map<String, dynamic>>? categories,
  }) {
    return {
      'id': 'salon-1',
      'name': 'Glow Up Studio',
      'slug': 'glow-up-studio',
      'description': 'Luxury salon experience.',
      'address': 'MG Road, Pune',
      'city': 'Pune',
      'pincode': '411001',
      'latitude': 18.5204,
      'longitude': 73.8567,
      'gender_focus': 'Unisex',
      'cover_photo_url': '',
      'gallery': [],
      'rating': {'average': 4.5, 'count': 25},
      'advance_required': true,
      'advance_refundable': true,
      'advance_percentage_default': 25.0,
      'is_favourited': false,
      'is_bookable': true,
      'unavailable_reason': null,
      'is_open_now': true,
      'open_status_label': 'Open now · closes 9:00 PM',
      'today_hours': '10:00 AM - 9:00 PM',
      'working_hours': [],
      'upcoming_closures': [],
      'categories': categories ?? [
        {'id': 'cat-hair', 'name': 'Hair', 'service_count': services.where((s) => s['category_id'] == 'cat-hair').length},
        {'id': 'cat-skin', 'name': 'Skin', 'service_count': services.where((s) => s['category_id'] == 'cat-skin').length},
      ],
      'services': services,
      'combos': [],
      'team': [
        {'id': 'staff-1', 'name': 'Alex'},
      ],
    };
  }

  void setupHttpMocks(Map<String, dynamic> salonData, {List<dynamic>? cartItems}) {
    final currentCartItems = List<dynamic>.from(cartItems ?? []);
    api.debugSetClient(
      MockClient((request) async {
        final path = request.url.path;
        if (path.contains('/customer/salons/')) {
          if (path.contains('/reviews')) {
            return http.Response(
              jsonEncode({
                'reviews': [],
                'meta': {'has_more': false},
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({'salon': salonData, 'is_favourited': false}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path.contains('/customer/cart')) {
          if (request.method == 'POST') {
            final body = jsonDecode(request.body);
            final sId = body['service_id'];
            currentCartItems.add({
              'id': 'cart-item-${currentCartItems.length + 1}',
              'service_id': sId,
              'quantity': 1,
              'price': 200.0,
            });
            CartService.globalCartNotifier.value = {
              'items': currentCartItems,
              'summary': {'total_items': currentCartItems.length, 'total_price': 200.0},
            };
            return http.Response(
              jsonEncode({
                'items': currentCartItems,
                'summary': {'total_items': currentCartItems.length, 'total_price': 200.0},
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'items': currentCartItems,
              'summary': {'total_items': currentCartItems.length, 'total_price': 0.0},
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
  }

  group('Salon Details - Services Listing Popularity and Exploration', () {
    testWidgets(
      'displays only top 5 services ordered by booking popularity initially, with Explore All Services button',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 3500));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final sampleServices = [
          {
            'id': 'srv-1',
            'name': 'Basic Haircut',
            'price': 250.0,
            'duration_minutes': 30,
            'category_id': 'cat-hair',
            'category_name': 'Hair',
            'provider_count': 2,
            'booking_count': 10,
          },
          {
            'id': 'srv-2',
            'name': 'Premium Hair Spa',
            'price': 800.0,
            'duration_minutes': 60,
            'category_id': 'cat-hair',
            'category_name': 'Hair',
            'provider_count': 2,
            'booking_count': 55, // Highest popularity (Rank 1)
          },
          {
            'id': 'srv-3',
            'name': 'Beard Styling',
            'price': 150.0,
            'duration_minutes': 20,
            'category_id': 'cat-hair',
            'category_name': 'Hair',
            'provider_count': 2,
            'booking_count': 30, // Rank 3
          },
          {
            'id': 'srv-4',
            'name': 'Head Massage',
            'price': 300.0,
            'duration_minutes': 30,
            'category_id': 'cat-hair',
            'category_name': 'Hair',
            'provider_count': 2,
            'booking_count': 5,
          },
          {
            'id': 'srv-5',
            'name': 'Hair Color',
            'price': 1200.0,
            'duration_minutes': 90,
            'category_id': 'cat-hair',
            'category_name': 'Hair',
            'provider_count': 2,
            'booking_count': 40, // Rank 2
          },
          {
            'id': 'srv-6',
            'name': 'Charcoal Facial',
            'price': 600.0,
            'duration_minutes': 45,
            'category_id': 'cat-skin',
            'category_name': 'Skin',
            'provider_count': 2,
            'booking_count': 25, // Rank 4
          },
          {
            'id': 'srv-7',
            'name': 'Fruit Bleach',
            'price': 350.0,
            'duration_minutes': 30,
            'category_id': 'cat-skin',
            'category_name': 'Skin',
            'provider_count': 2,
            'booking_count': 20, // Rank 5
          },
          {
            'id': 'srv-8',
            'name': 'Nail Art',
            'price': 400.0,
            'duration_minutes': 40,
            'category_id': 'cat-skin',
            'category_name': 'Skin',
            'provider_count': 2,
            'booking_count': 2,
          },
        ];

        final salonData = createSampleSalonWithServices(services: sampleServices);
        setupHttpMocks(salonData);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const SalonDetailScreen(
              salonId: 'salon-1',
              initialScrollToServices: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Top 5 services expected (by booking_count DESC):
        // 1. Premium Hair Spa (55)
        // 2. Hair Color (40)
        // 3. Beard Styling (30)
        // 4. Charcoal Facial (25)
        // 5. Fruit Bleach (20)
        expect(find.text('Premium Hair Spa'), findsOneWidget);
        expect(find.text('Hair Color'), findsOneWidget);
        expect(find.text('Beard Styling'), findsOneWidget);
        expect(find.text('Charcoal Facial'), findsOneWidget);
        expect(find.text('Fruit Bleach'), findsOneWidget);

        // Lower-ranked services should NOT be visible in compact mode
        expect(find.text('Basic Haircut'), findsNothing);
        expect(find.text('Head Massage'), findsNothing);
        expect(find.text('Nail Art'), findsNothing);

        // "Explore All Services" button must be present
        final exploreButton = find.byKey(const ValueKey('explore_all_services_button'));
        expect(exploreButton, findsOneWidget);
        expect(find.text('Explore All Services'), findsOneWidget);

        // Tap "Explore All Services"
        await tester.tap(exploreButton);
        await tester.pumpAndSettle();

        // Now button should say "Show Less"
        expect(find.text('Show Less'), findsOneWidget);

        // All 8 services should now be available in the expanded list
        expect(find.text('Premium Hair Spa'), findsOneWidget);
        expect(find.text('Hair Color'), findsOneWidget);
        expect(find.text('Beard Styling'), findsOneWidget);
        expect(find.text('Charcoal Facial'), findsOneWidget);
        expect(find.text('Fruit Bleach'), findsOneWidget);
        expect(find.text('Basic Haircut'), findsOneWidget);
        expect(find.text('Head Massage'), findsOneWidget);
        expect(find.text('Nail Art'), findsOneWidget);

        // Tap "Show Less" to collapse back
        final showLessButton = find.byKey(const ValueKey('explore_all_services_button'));
        await tester.tap(showLessButton);
        await tester.pumpAndSettle();

        // Should return to "Explore All Services"
        expect(find.text('Explore All Services'), findsOneWidget);
        expect(find.text('Nail Art'), findsNothing);
        expect(find.text('Head Massage'), findsNothing);
        expect(find.text('Basic Haircut'), findsNothing);
      },
    );

    testWidgets(
      'does not show Explore button when category has 5 or fewer services',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 3500));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final sampleServices = [
          {
            'id': 'srv-1',
            'name': 'Haircut 1',
            'price': 200.0,
            'duration_minutes': 30,
            'category_id': 'cat-hair',
            'category_name': 'Hair',
            'provider_count': 1,
            'booking_count': 5,
          },
          {
            'id': 'srv-2',
            'name': 'Haircut 2',
            'price': 250.0,
            'duration_minutes': 30,
            'category_id': 'cat-hair',
            'category_name': 'Hair',
            'provider_count': 1,
            'booking_count': 3,
          },
          {
            'id': 'srv-3',
            'name': 'Haircut 3',
            'price': 300.0,
            'duration_minutes': 30,
            'category_id': 'cat-hair',
            'category_name': 'Hair',
            'provider_count': 1,
            'booking_count': 1,
          },
        ];

        final salonData = createSampleSalonWithServices(services: sampleServices);
        setupHttpMocks(salonData);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const SalonDetailScreen(
              salonId: 'salon-1',
              initialScrollToServices: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // All 3 services are visible
        expect(find.text('Haircut 1'), findsOneWidget);
        expect(find.text('Haircut 2'), findsOneWidget);
        expect(find.text('Haircut 3'), findsOneWidget);

        // No Explore All Services button needed since count <= 5
        expect(find.byKey(const ValueKey('explore_all_services_button')), findsNothing);
      },
    );

    testWidgets(
      'category tab selection resets expansion state and filters by category popularity',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 3500));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final sampleServices = [
          // Hair services (6 services)
          {'id': 'h-1', 'name': 'Haircut A', 'price': 200.0, 'duration_minutes': 30, 'category_id': 'cat-hair', 'category_name': 'Hair', 'provider_count': 1, 'booking_count': 50},
          {'id': 'h-2', 'name': 'Haircut B', 'price': 200.0, 'duration_minutes': 30, 'category_id': 'cat-hair', 'category_name': 'Hair', 'provider_count': 1, 'booking_count': 40},
          {'id': 'h-3', 'name': 'Haircut C', 'price': 200.0, 'duration_minutes': 30, 'category_id': 'cat-hair', 'category_name': 'Hair', 'provider_count': 1, 'booking_count': 30},
          {'id': 'h-4', 'name': 'Haircut D', 'price': 200.0, 'duration_minutes': 30, 'category_id': 'cat-hair', 'category_name': 'Hair', 'provider_count': 1, 'booking_count': 20},
          {'id': 'h-5', 'name': 'Haircut E', 'price': 200.0, 'duration_minutes': 30, 'category_id': 'cat-hair', 'category_name': 'Hair', 'provider_count': 1, 'booking_count': 10},
          {'id': 'h-6', 'name': 'Haircut F', 'price': 200.0, 'duration_minutes': 30, 'category_id': 'cat-hair', 'category_name': 'Hair', 'provider_count': 1, 'booking_count': 1},
          // Skin service (1 service)
          {'id': 's-1', 'name': 'Facial Glow', 'price': 500.0, 'duration_minutes': 45, 'category_id': 'cat-skin', 'category_name': 'Skin', 'provider_count': 1, 'booking_count': 99},
        ];

        final salonData = createSampleSalonWithServices(services: sampleServices);
        setupHttpMocks(salonData);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const SalonDetailScreen(
              salonId: 'salon-1',
              initialScrollToServices: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // In All Services (7 total):
        // Top 5: Facial Glow (99), Haircut A (50), Haircut B (40), Haircut C (30), Haircut D (20)
        expect(find.text('Facial Glow'), findsOneWidget);
        expect(find.text('Haircut A'), findsOneWidget);
        expect(find.text('Haircut F'), findsNothing);

        // Switch to Hair tab
        final hairTab = find.text('Hair (6)');
        expect(hairTab, findsOneWidget);
        await tester.tap(hairTab);
        await tester.pumpAndSettle();

        // In Hair tab:
        // Top 5: Haircut A, B, C, D, E (Haircut F is hidden)
        expect(find.text('Haircut A'), findsOneWidget);
        expect(find.text('Haircut E'), findsOneWidget);
        expect(find.text('Haircut F'), findsNothing);
        expect(find.text('Facial Glow'), findsNothing);

        // Explore All Services button is present because 6 > 5
        final exploreHairBtn = find.byKey(const ValueKey('explore_all_services_button'));
        expect(exploreHairBtn, findsOneWidget);

        // Expand Hair tab
        await tester.tap(exploreHairBtn);
        await tester.pumpAndSettle();

        // Haircut F is now visible
        expect(find.text('Haircut F'), findsOneWidget);

        // Switch to Skin tab
        final skinTab = find.text('Skin (1)');
        expect(skinTab, findsOneWidget);
        await tester.tap(skinTab);
        await tester.pumpAndSettle();

        // In Skin tab: only Facial Glow
        expect(find.text('Facial Glow'), findsOneWidget);
        expect(find.text('Haircut A'), findsNothing);
        // No button because count is 1 <= 5
        expect(find.byKey(const ValueKey('explore_all_services_button')), findsNothing);
      },
    );
  });
}
