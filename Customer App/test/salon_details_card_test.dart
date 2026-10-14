import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:customer_app/screens/salon_detail_screen.dart';
import 'package:customer_app/services/http_client.dart' as api;
import 'package:customer_app/theme/app_theme.dart';

class MockUrlLauncherPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {
  String? lastLaunchedUrl;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    lastLaunchedUrl = url;
    return true;
  }
}

void main() {
  late MockUrlLauncherPlatform mockUrlLauncher;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'auth_token': 'dummy_token'});
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost/api');
    mockUrlLauncher = MockUrlLauncherPlatform();
    UrlLauncherPlatform.instance = mockUrlLauncher;
  });

  Map<String, dynamic> createSampleSalon({
    String id = 'salon-1',
    String name = 'The Style Loft',
    dynamic latitude = 18.5590,
    dynamic longitude = 73.7868,
    String address = '3rd Floor, Baner Road, Pune',
    String city = 'Pune',
    String pincode = '401988',
  }) {
    return {
      'id': id,
      'name': name,
      'slug': 'the-style-loft',
      'description': 'Neighbourhood salon with a loyal regular crowd.',
      'address': address,
      'city': city,
      'pincode': pincode,
      'latitude': latitude,
      'longitude': longitude,
      'gender_focus': 'Unisex',
      'cover_photo_url': '',
      'gallery': [],
      'rating': {'average': 4.1, 'count': 17},
      'advance_required': true,
      'advance_refundable': true,
      'advance_percentage_default': 30.0,
      'is_favourited': false,
      'is_bookable': true,
      'unavailable_reason': null,
      'is_open_now': true,
      'open_status_label': 'Open now · closes 8:00 PM',
      'today_hours': '10:00 AM - 8:00 PM',
      'working_hours': [],
      'upcoming_closures': [],
      'categories': [],
      'services': [
        {
          'id': 'srv-1',
          'template_id': 'tpl-1',
          'name': 'Haircut & Styling',
          'description': 'Classic haircut',
          'price': 450.0,
          'duration_minutes': 30,
          'category_id': 'cat-1',
          'category_name': 'Hair',
          'gender_focus': 'Unisex',
          'advance_percentage': 30.0,
          'refundable_advance': true,
          'provider_count': 3,
        },
      ],
      'combos': [],
      'team': [
        {'id': 'staff-1', 'name': 'John'},
        {'id': 'staff-2', 'name': 'Sarah'},
        {'id': 'staff-3', 'name': 'Mike'},
      ],
    };
  }

  void setupHttpMocks(Map<String, dynamic> salonData) {
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
          return http.Response(
            jsonEncode({'items': [], 'summary': {}}),
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

  group('Salon Details Card - Icon Button and Clickable Address Tests', () {
    testWidgets(
      'replaces text Direct/Directions button with upper-right directions icon button and makes address & pin clickable',
      (tester) async {
        final salon = createSampleSalon();
        setupHttpMocks(salon);

        await tester.binding.setSurfaceSize(const Size(390, 844));

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const SalonDetailScreen(salonId: 'salon-1'),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // 1. Verify visible "Direct" or "Directions" text button is NOT present
        expect(find.text('Direct'), findsNothing);
        expect(find.text('Directions'), findsNothing);

        // 2. Verify directions icon-only button is present in upper-right with tooltip & semantics
        final directionsIconFinder = find.byIcon(Icons.directions_outlined);
        expect(directionsIconFinder, findsOneWidget);
        expect(find.byTooltip('Get directions'), findsOneWidget);

        // 3. Verify location pin icon and full address are displayed
        expect(find.byIcon(Icons.location_on_outlined), findsOneWidget);
        expect(
          find.text('3rd Floor, Baner Road, Pune, Pune, 401988'),
          findsOneWidget,
        );

        // 4. Test tapping Upper-Right Directions Icon Button launches maps with coordinates
        await tester.tap(directionsIconFinder);
        await tester.pumpAndSettle();

        expect(mockUrlLauncher.lastLaunchedUrl, isNotNull);
        expect(
          mockUrlLauncher.lastLaunchedUrl,
          contains(
            'https://www.google.com/maps/search/?api=1&query=18.559%2C73.7868',
          ),
        );

        // Reset launched URL
        mockUrlLauncher.lastLaunchedUrl = null;

        // 5. Test tapping location pin icon opens same destination
        final pinIconFinder = find.byIcon(Icons.location_on_outlined);
        await tester.tap(pinIconFinder);
        await tester.pumpAndSettle();

        expect(mockUrlLauncher.lastLaunchedUrl, isNotNull);
        expect(
          mockUrlLauncher.lastLaunchedUrl,
          contains(
            'https://www.google.com/maps/search/?api=1&query=18.559%2C73.7868',
          ),
        );

        // Reset launched URL
        mockUrlLauncher.lastLaunchedUrl = null;

        // 6. Test tapping complete address text opens same destination
        final addressTextFinder = find.text(
          '3rd Floor, Baner Road, Pune, Pune, 401988',
        );
        await tester.tap(addressTextFinder);
        await tester.pumpAndSettle();

        expect(mockUrlLauncher.lastLaunchedUrl, isNotNull);
        expect(
          mockUrlLauncher.lastLaunchedUrl,
          contains(
            'https://www.google.com/maps/search/?api=1&query=18.559%2C73.7868',
          ),
        );
      },
    );

    testWidgets(
      'prefers coordinates when valid and falls back to address when coordinates are missing or 0',
      (tester) async {
        // Salon with 0,0 invalid coordinates
        final salonWithoutCoords = createSampleSalon(
          latitude: 0.0,
          longitude: 0.0,
          name: 'The Style Loft',
          address: '3rd Floor, Baner Road',
          city: 'Pune',
          pincode: '401988',
        );
        setupHttpMocks(salonWithoutCoords);

        await tester.binding.setSurfaceSize(const Size(390, 844));

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const SalonDetailScreen(salonId: 'salon-1'),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Tap directions icon button
        final directionsIconFinder = find.byIcon(Icons.directions_outlined);
        await tester.tap(directionsIconFinder);
        await tester.pumpAndSettle();

        expect(mockUrlLauncher.lastLaunchedUrl, isNotNull);
        // Should fallback to name + address search query properly encoded
        expect(
          mockUrlLauncher.lastLaunchedUrl,
          contains(
            'https://www.google.com/maps/search/?api=1&query=The+Style+Loft%2C+3rd+Floor%2C+Baner+Road%2C+Pune%2C+401988',
          ),
        );
      },
    );

    testWidgets('handles long salon names on narrow screens without overflow', (
      tester,
    ) async {
      final salonLongName = createSampleSalon(
        name:
            'Very Long Luxury Salon and Wellness Spa Center Baner Pune Branch',
        address:
            'Shop 101, 3rd Floor, High Street Plaza, Baner Road, Pune, Maharashtra, 401988',
      );
      setupHttpMocks(salonLongName);

      // Compact Android screen (360px width)
      await tester.binding.setSurfaceSize(const Size(360, 640));

      FlutterErrorDetails? errorDetails;
      final oldOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        errorDetails = details;
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const SalonDetailScreen(salonId: 'salon-1'),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      FlutterError.onError = oldOnError;

      expect(errorDetails, isNull);
      expect(find.byIcon(Icons.directions_outlined), findsOneWidget);
      expect(find.textContaining('Very Long Luxury Salon'), findsNWidgets(2));
    });

    testWidgets('shows graceful toast when location details are unavailable', (
      tester,
    ) async {
      final salonNoLocation = createSampleSalon(
        name: '',
        address: '',
        city: '',
        pincode: '',
        latitude: null,
        longitude: null,
      );
      setupHttpMocks(salonNoLocation);

      await tester.binding.setSurfaceSize(const Size(390, 844));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const SalonDetailScreen(salonId: 'salon-1'),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap directions icon button
      final directionsIconFinder = find.byIcon(Icons.directions_outlined);
      await tester.tap(directionsIconFinder);
      await tester.pump();

      // No map URL launched
      expect(mockUrlLauncher.lastLaunchedUrl, isNull);
      // Toast message shown
      expect(
        find.text('Location details are unavailable for this salon.'),
        findsOneWidget,
      );
    });
  });
}
