import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:customer_app/models/category.dart';
import 'package:customer_app/screens/category_salons_screen.dart';
import 'package:customer_app/widgets/discovery_salon_card.dart';

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost/api');
  });

  group('CategorySalonsScreen & DiscoverySalonCard Redesign Tests', () {
    testWidgets('DiscoverySalonCard renders photo, badge, info, services, and selects on tap', (tester) async {
      final sampleSalon = {
        'id': 'salon-1',
        'name': 'Glow Up Studio',
        'address': 'Koregaon Park, Pune',
        'cover_photo_url': 'https://example.com/cover.jpg',
        'avg_rating': 4.5,
        'review_count': 120,
        'distance_km': 2.5,
        'photos_count': 8,
        'is_open_now': true,
        'open_status_label': 'Open • Closes 9:00 PM',
        'category_services': [
          {'id': 'svc-1', 'name': "Men's Haircut", 'price': 350},
          {'id': 'svc-2', 'name': 'Hair Spa', 'price': 999},
          {'id': 'svc-3', 'name': 'Hair Colour', 'price': 1499},
        ],
      };

      Map<String, dynamic>? selectedService;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiscoverySalonCard(
              salon: sampleSalon,
              categoryId: 'cat-hair',
              categoryName: 'Hair',
              onToggleFavourite: () {},
              onServiceSelected: (svc) {
                selectedService = svc;
              },
            ),
          ),
        ),
      );

      await tester.pump();

      // Verify salon name, reviews, location, distance
      expect(find.text('Glow Up Studio'), findsOneWidget);
      expect(find.text('4.5'), findsOneWidget);
      expect(find.text('(120 reviews)'), findsOneWidget);
      expect(find.text('Koregaon Park, Pune'), findsOneWidget);
      expect(find.text('2.5 km'), findsOneWidget);
      expect(find.text('8+ Photos'), findsOneWidget);
      expect(find.text('Open • Closes 9:00 PM'), findsOneWidget);

      // Verify service chips
      expect(find.text("Men's Haircut"), findsOneWidget);
      expect(find.text('₹350'), findsOneWidget);
      expect(find.text('Hair Spa'), findsOneWidget);
      expect(find.text('₹999'), findsOneWidget);
      expect(find.text('Hair Colour'), findsOneWidget);
      expect(find.text('₹1499'), findsOneWidget);

      // Verify CTA button
      expect(find.text('View Salon & Book'), findsOneWidget);

      // Tap on a service chip to select it
      await tester.tap(find.text("Men's Haircut"));
      await tester.pump();

      expect(selectedService, isNotNull);
      expect(selectedService!['name'], "Men's Haircut");
    });

    testWidgets('DiscoverySalonCard deselects service when tapped again', (tester) async {
      final sampleSalon = {
        'id': 'salon-1',
        'name': 'Glow Up Studio',
        'address': 'Koregaon Park, Pune',
        'category_services': [
          {'id': 'svc-1', 'name': "Men's Haircut", 'price': 350},
        ],
      };

      Map<String, dynamic>? selectedService;
      Map<String, dynamic>? deselectedService;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiscoverySalonCard(
              salon: sampleSalon,
              categoryId: 'cat-hair',
              categoryName: 'Hair',
              onToggleFavourite: () {},
              onServiceSelected: (svc) => selectedService = svc,
              onServiceDeselected: (svc) => deselectedService = svc,
            ),
          ),
        ),
      );

      await tester.pump();

      // Tap once to select
      await tester.tap(find.text("Men's Haircut"));
      await tester.pump();
      expect(selectedService?['id'], 'svc-1');
      expect(deselectedService, isNull);

      // Tap again to deselect
      await tester.tap(find.text("Men's Haircut"));
      await tester.pump();
      expect(deselectedService?['id'], 'svc-1');
    });

    testWidgets('CategorySalonsScreen renders header, search, and category pills', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CategorySalonsScreen(
            category: ServiceCategory(id: 'combo', name: 'Hair'),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Verify category title and search
      expect(find.text('Hair'), findsWidgets);
      expect(find.textContaining('Find the best hair salons'), findsOneWidget);
      expect(find.text('Search salons or services...'), findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    });
  });
}
