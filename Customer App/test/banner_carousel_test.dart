import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/models/banner.dart';
import 'package:customer_app/widgets/banner_carousel.dart';
import 'package:customer_app/theme/app_theme.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: child,
      ),
    );
  }

  group('BannerCarousel Widget', () {
    testWidgets('renders empty state when banner list is empty', (tester) async {
      await tester.pumpWidget(wrap(const BannerCarousel(banners: [])));
      await tester.pumpAndSettle();

      expect(find.text('No active offers right now'), findsOneWidget);
      expect(find.text('Check back later for exciting spa and salon deals!'), findsOneWidget);
    });

    testWidgets('renders static and animated banners without crashing', (tester) async {
      final banners = [
        PromoBanner(
          id: '1',
          title: 'Static Offer 1',
          imageUrl: 'https://via.placeholder.com/800x320.jpg',
          mediaKind: 'image',
          targetScope: 'platform',
        ),
        PromoBanner(
          id: '2',
          title: 'Animated GIF Offer 2',
          imageUrl: 'https://via.placeholder.com/800x320.gif',
          mediaKind: 'animated',
          targetScope: 'platform',
        ),
        PromoBanner(
          id: '3',
          title: 'Animated WebP Offer 3',
          imageUrl: 'https://via.placeholder.com/800x320.webp',
          mediaKind: 'animated',
          targetScope: 'platform',
        ),
      ];

      await tester.pumpWidget(wrap(BannerCarousel(banners: banners, autoPlay: false)));
      await tester.pump();

      expect(find.byType(PageView), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
      expect(find.text('Static Offer 1'), findsOneWidget);
    });

    testWidgets('broken image URL does not crash carousel or throw unhandled exceptions', (tester) async {
      final banners = [
        PromoBanner(
          id: 'broken-1',
          title: 'Broken Banner',
          imageUrl: 'https://invalid-host-that-does-not-exist.test/image.gif',
          mediaKind: 'animated',
          targetScope: 'platform',
        ),
      ];

      await tester.pumpWidget(wrap(BannerCarousel(banners: banners, autoPlay: false)));
      await tester.pump();

      // Broken image triggers errorBuilder and renders cleanly
      expect(find.byType(BannerCarousel), findsOneWidget);
      expect(find.text('Broken Banner'), findsOneWidget);
    });

    testWidgets('single banner does not enable infinite loop or throw timer exceptions', (tester) async {
      final banners = [
        PromoBanner(
          id: '1',
          title: 'Single Banner',
          imageUrl: 'https://via.placeholder.com/800x320.png',
          mediaKind: 'image',
          targetScope: 'platform',
        ),
      ];

      await tester.pumpWidget(wrap(BannerCarousel(banners: banners, autoPlay: true)));
      await tester.pump();

      // Advance time to verify auto-play is inactive for a single banner
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Single Banner'), findsOneWidget);
    });

    testWidgets('swiping between static and animated banners works smoothly', (tester) async {
      final banners = [
        PromoBanner(
          id: '1',
          title: 'Banner A',
          imageUrl: 'https://via.placeholder.com/800x320.jpg',
          mediaKind: 'image',
          targetScope: 'platform',
        ),
        PromoBanner(
          id: '2',
          title: 'Banner B (Animated)',
          imageUrl: 'https://via.placeholder.com/800x320.gif',
          mediaKind: 'animated',
          targetScope: 'platform',
        ),
      ];

      await tester.pumpWidget(wrap(BannerCarousel(banners: banners, autoPlay: false)));
      await tester.pump();

      expect(find.text('Banner A'), findsOneWidget);

      // Swipe to next page
      await tester.fling(find.byType(PageView), const Offset(-600, 0), 2000);
      await tester.pumpAndSettle();

      expect(find.text('Banner B (Animated)'), findsOneWidget);
    });

    testWidgets('respects disableAnimations reduced motion setting', (tester) async {
      final banners = [
        PromoBanner(
          id: '1',
          title: 'Banner 1',
          imageUrl: 'https://via.placeholder.com/800x320.jpg',
          mediaKind: 'image',
          targetScope: 'platform',
        ),
        PromoBanner(
          id: '2',
          title: 'Banner 2',
          imageUrl: 'https://via.placeholder.com/800x320.gif',
          mediaKind: 'animated',
          targetScope: 'platform',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: BannerCarousel(banners: banners, autoPlay: true),
            ),
          ),
        ),
      );
      await tester.pump();

      // Ensure banner 1 is visible
      expect(find.text('Banner 1'), findsOneWidget);

      // Advance time beyond 4 seconds
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();

      // Banner 1 should still be visible because disableAnimations disabled auto-slide
      expect(find.text('Banner 1'), findsOneWidget);
    });

    testWidgets('mixed carousel (static, animated, static, animated) cycles correctly', (tester) async {
      final banners = [
        PromoBanner(id: '1', title: 'Static 1', imageUrl: 'https://via.placeholder.com/1.jpg', mediaKind: 'image', targetScope: 'platform'),
        PromoBanner(id: '2', title: 'Animated 2', imageUrl: 'https://via.placeholder.com/2.gif', mediaKind: 'animated', targetScope: 'platform'),
        PromoBanner(id: '3', title: 'Static 3', imageUrl: 'https://via.placeholder.com/3.png', mediaKind: 'image', targetScope: 'platform'),
        PromoBanner(id: '4', title: 'Animated 4', imageUrl: 'https://via.placeholder.com/4.webp', mediaKind: 'animated', targetScope: 'platform'),
      ];

      await tester.pumpWidget(wrap(BannerCarousel(banners: banners, autoPlay: false)));
      await tester.pump();

      expect(find.text('Static 1'), findsOneWidget);

      // Fling forward to Animated 2
      await tester.fling(find.byType(PageView), const Offset(-600, 0), 2000);
      await tester.pumpAndSettle();
      expect(find.text('Animated 2'), findsOneWidget);

      // Fling forward to Static 3
      await tester.fling(find.byType(PageView), const Offset(-600, 0), 2000);
      await tester.pumpAndSettle();
      expect(find.text('Static 3'), findsOneWidget);

      // Fling forward to Animated 4
      await tester.fling(find.byType(PageView), const Offset(-600, 0), 2000);
      await tester.pumpAndSettle();
      expect(find.text('Animated 4'), findsOneWidget);
    });
  });
}
