import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:customer_app/screens/combo_detail_screen.dart';
import 'package:customer_app/theme/app_theme.dart';

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost/api');
  });
  final testSalon = {
    'id': 101,
    'name': 'Glow & Glam Studio',
    'address': 'MG Road, Pune',
    'distance_km': 2.5,
    'avg_rating': 4.8,
    'review_count': 42,
    'is_serviceable': true,
    'cover_photo_url': '',
  };

  final testComboShort = {
    'id': 201,
    'name': 'Express Glow Package',
    'price': 499,
    'original_price': 899,
    'duration_minutes': 45,
    'services': [
      {'name': 'Basic Haircut', 'description': 'Precision cut and style'},
      {'name': 'Express Facial', 'description': 'Deep cleansing and hydration'},
    ],
  };

  final testComboLong = {
    'id': 202,
    'name': 'Bridal Luxury Combo',
    'price': 2999,
    'original_price': 4999,
    'duration_minutes': 180,
    'services': [
      {'name': 'Hair Spa & Treatment', 'description': 'Intense nourishing ritual'},
      {'name': 'Gold Facial', 'description': 'Radiance-boosting luxury mask'},
      {'name': 'Manicure Deluxe', 'description': 'Complete nail care and massage'},
      {'name': 'Pedicure Deluxe', 'description': 'Exfoliating foot therapy'},
      {'name': 'Threading & Waxing', 'description': 'Full face and arms cleanup'},
      {'name': 'Hair Styling', 'description': 'Blowdry and iron curling'},
    ],
  };

  Widget wrap(Widget child, {EdgeInsets? mediaQueryPadding}) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 850),
          padding: mediaQueryPadding ?? const EdgeInsets.only(bottom: 115), // Shell navigation footprint
        ),
        child: child,
      ),
    );
  }

  group('ComboDetailScreen Layout and Rendering Tests', () {
    testWidgets('renders short combo content with clean hierarchy and sticky CTA', (tester) async {
      await tester.pumpWidget(wrap(ComboDetailScreen(
        salon: testSalon,
        combo: testComboShort,
      )));
      await tester.pumpAndSettle();

      // Verify Header & Identity
      expect(find.text('Express Glow Package'), findsOneWidget);
      expect(find.text('at Glow & Glam Studio'), findsOneWidget);
      expect(find.text('4.8'), findsOneWidget);
      expect(find.text('(42 reviews)'), findsOneWidget);

      // Verify Price & Savings
      expect(find.text('₹499'), findsOneWidget);
      expect(find.text('₹899'), findsOneWidget);
      expect(find.text('44% OFF'), findsOneWidget);
      expect(find.text('✨ You save ₹400'), findsOneWidget);

      // Scroll to reveal included services
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();

      // Verify Included Services
      expect(find.text('What\'s included'), findsOneWidget);
      expect(find.text('Basic Haircut'), findsOneWidget);
      expect(find.text('Express Facial'), findsOneWidget);

      // Verify Sticky CTA button
      expect(find.text('Book This Combo'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('renders long combo content and scrolls smoothly without overflow', (tester) async {
      await tester.pumpWidget(wrap(ComboDetailScreen(
        salon: testSalon,
        combo: testComboLong,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Bridal Luxury Combo'), findsOneWidget);

      // Scroll to bottom
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.text('What\'s included'), findsOneWidget);

      // Bottom services are now visible
      expect(find.text('Hair Styling'), findsOneWidget);

      // Sticky CTA button remains pinned and visible
      expect(find.text('Book This Combo'), findsOneWidget);
    });

    testWidgets('CTA button is disabled when salon is unserviceable', (tester) async {
      final unserviceableSalon = {
        ...testSalon,
        'is_serviceable': false,
        'unavailable_reason': 'Temporarily closed',
      };

      await tester.pumpWidget(wrap(ComboDetailScreen(
        salon: unserviceableSalon,
        combo: testComboShort,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Temporarily closed'), findsOneWidget);

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
    });
  });
}
