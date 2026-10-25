import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:customer_app/models/category.dart';
import 'package:customer_app/screens/category_salons_screen.dart';
import 'package:customer_app/screens/salon_detail_screen.dart';
import 'package:customer_app/widgets/discovery_salon_card.dart';

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost/api');
  });

  group('CategorySalonsScreen & DiscoverySalonCard Redesign Tests', () {
    testWidgets('DiscoverySalonCard renders clean compact card with photo, info, and View Salon & Book button without mini service cards', (tester) async {
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

      bool favToggled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiscoverySalonCard(
              salon: sampleSalon,
              categoryId: 'cat-hair',
              categoryName: 'Hair',
              onToggleFavourite: () {
                favToggled = true;
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

      // Verify mini service cards, names, and prices are REMOVED from the card
      expect(find.text("Men's Haircut"), findsNothing);
      expect(find.text('₹350'), findsNothing);
      expect(find.text('Hair Spa'), findsNothing);
      expect(find.text('₹999'), findsNothing);
      expect(find.text('Hair Colour'), findsNothing);
      expect(find.text('₹1499'), findsNothing);

      // Verify prominent CTA button
      expect(find.text('View Salon & Book'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);

      // Verify favourite button works
      await tester.tap(find.byIcon(Icons.favorite_border));
      expect(favToggled, isTrue);
    });

    testWidgets('Tapping View Salon & Book navigates to SalonDetailScreen', (tester) async {
      final sampleSalon = {
        'id': 'salon-1',
        'name': 'Glow Up Studio',
        'address': 'Koregaon Park, Pune',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiscoverySalonCard(
              salon: sampleSalon,
              categoryId: 'cat-hair',
              categoryName: 'Hair',
              onToggleFavourite: () {},
            ),
          ),
        ),
      );

      await tester.pump();

      // Tap View Salon & Book
      await tester.tap(find.text('View Salon & Book'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify SalonDetailScreen is pushed
      expect(find.byType(SalonDetailScreen), findsOneWidget);
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
