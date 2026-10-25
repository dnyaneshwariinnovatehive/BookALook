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

  tearDown(() {
    CartService.globalCartNotifier.value = null;
  });

  Map<String, dynamic> createSampleSalon() {
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
      'categories': [
        {'id': 'cat-1', 'name': 'Hair', 'service_count': 1},
      ],
      'services': [
        {
          'id': 'srv-1',
          'template_id': 'tpl-1',
          'name': 'Haircut & Blowdry',
          'description': 'Complete style and cut',
          'price': 500.0,
          'duration_minutes': 45,
          'category_id': 'cat-1',
          'category_name': 'Hair',
          'gender_focus': 'Unisex',
          'advance_percentage': 25.0,
          'refundable_advance': true,
          'provider_count': 2,
        },
      ],
      'combos': [],
      'team': [
        {'id': 'staff-1', 'name': 'Alex'},
      ],
    };
  }

  void setupHttpMocks(Map<String, dynamic> salonData) {
    var cartItems = <Map<String, dynamic>>[];
    api.debugSetClient(
      MockClient((request) async {
        final path = request.url.path;

        if (path.contains('/customer/salons/salon-1/cart/items') && request.method == 'POST') {
          final body = jsonDecode(request.body);
          final sId = body['service_id'];
          cartItems = [
            <String, dynamic>{
              'id': 1,
              'service_id': sId,
              'quantity': 1,
              'price': 500.0,
              'service': <String, dynamic>{'id': sId, 'name': 'Haircut & Blowdry'},
            },
          ];
          final cartObj = <String, dynamic>{
            'id': 'cart-1',
            'salon_id': 'salon-1',
            'items': cartItems,
            'summary': <String, dynamic>{'total_items': 1, 'total_price': 500.0},
          };
          CartService.globalCartNotifier.value = cartObj;
          return http.Response(
            jsonEncode({'cart': cartObj}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (path.contains('/customer/cart/items') && request.method == 'DELETE') {
          cartItems = [];
          final emptyCart = <String, dynamic>{
            'id': 'cart-1',
            'salon_id': 'salon-1',
            'items': [],
            'summary': <String, dynamic>{'total_items': 0, 'total_price': 0.0},
          };
          CartService.globalCartNotifier.value = emptyCart;
          return http.Response(
            jsonEncode({'success': true, 'cart': emptyCart}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (path.contains('/customer/cart') && request.method == 'GET') {
          final cartObj = <String, dynamic>{
            'id': 'cart-1',
            'salon_id': 'salon-1',
            'items': cartItems,
            'summary': <String, dynamic>{'total_items': cartItems.length, 'total_price': cartItems.isEmpty ? 0.0 : 500.0},
          };
          return http.Response(
            jsonEncode({'cart': cartObj}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

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

        return http.Response('{}', 200, headers: {'content-type': 'application/json'});
      }),
    );
  }

  testWidgets(
    'service card has compact height and selecting service does NOT increase card size',
    (tester) async {
      final salonData = createSampleSalon();
      setupHttpMocks(salonData);

      await tester.binding.setSurfaceSize(const Size(400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const SalonDetailScreen(salonId: 'salon-1'),
        ),
      );

      await tester.pumpAndSettle();

      // Find the service card
      final serviceNameFinder = find.text('Haircut & Blowdry');
      expect(serviceNameFinder, findsOneWidget);

      final cardFinder = find.ancestor(
        of: serviceNameFinder,
        matching: find.byType(Container),
      ).first;

      final Size unselectedSize = tester.getSize(cardFinder);

      // Verify ADD button is present
      final addButtonFinder = find.byKey(const ValueKey('add_service_button'));
      expect(addButtonFinder, findsOneWidget);

      // Tap ADD button to select service
      await tester.tap(addButtonFinder);
      await tester.pumpAndSettle();

      // Verify ADDED button state is present
      expect(find.byKey(const ValueKey('added_service_container')), findsOneWidget);

      final Size selectedSize = tester.getSize(cardFinder);

      // CRITICAL ASSERTION: The card size must NOT be increased after selection
      expect(
        selectedSize.height,
        lessThanOrEqualTo(unselectedSize.height),
        reason: 'Selected card height (${selectedSize.height}) must not exceed unselected card height (${unselectedSize.height})',
      );
      expect(
        selectedSize.width,
        equals(unselectedSize.width),
        reason: 'Selected card width must match unselected card width',
      );

      // Deselect the service
      final removeButtonFinder = find.byKey(const ValueKey('remove_service_button'));
      expect(removeButtonFinder, findsOneWidget);
      await tester.tap(removeButtonFinder);
      await tester.pumpAndSettle();

      // Verify back to ADD button
      expect(find.byKey(const ValueKey('add_service_button')), findsOneWidget);
      final Size deselectedSize = tester.getSize(cardFinder);
      expect(deselectedSize.height, equals(unselectedSize.height));
    },
  );
}
