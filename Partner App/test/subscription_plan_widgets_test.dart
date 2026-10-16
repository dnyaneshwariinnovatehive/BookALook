import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/models/subscription_plan.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/widgets/subscription/plan_feature_item.dart';
import 'package:partner_app/widgets/subscription/subscription_plan_card.dart';

Widget _wrapWithTheme(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  group('PlanFeatureItem Widget Tests', () {
    testWidgets('Renders included feature with label, badge, and description', (tester) async {
      const feature = PlanFeature(
        key: 'whatsapp_campaign_limit',
        label: 'WhatsApp Campaigns',
        description: 'Promotional and automated campaign allowance',
        icon: Icons.campaign_outlined,
        isIncluded: true,
        tierBadge: '250/cycle',
        formattedValue: '250 campaigns per cycle',
      );

      await tester.pumpWidget(_wrapWithTheme(const PlanFeatureItem(feature: feature)));
      await tester.pumpAndSettle();

      expect(find.text('WhatsApp Campaigns'), findsOneWidget);
      expect(find.text('250/cycle'), findsOneWidget);
      expect(find.text('Promotional and automated campaign allowance'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('Omitted when isIncluded is false and showExcludedState is false', (tester) async {
      const feature = PlanFeature(
        key: 'has_priority_visibility',
        label: 'Priority Search Visibility',
        icon: Icons.verified_rounded,
        isIncluded: false,
      );

      await tester.pumpWidget(_wrapWithTheme(const PlanFeatureItem(feature: feature)));
      await tester.pumpAndSettle();

      expect(find.text('Priority Search Visibility'), findsNothing);
    });
  });

  group('SubscriptionPlanCard Widget Tests', () {
    final growthPlan = SubscriptionPlan.fromJson({
      'id': 'growth-uuid-1',
      'name': 'Growth',
      'price': 2999,
      'validity_days': 30,
      'whatsapp_campaign_limit': 1000,
      'has_customer_segmentation': true,
      'has_service_based_targeting': true,
      'has_high_value_targeting': true,
      'has_advanced_insights': true,
      'has_upsell_recommendations': 'advanced',
      'has_cross_sell_recommendations': 'advanced',
      'has_priority_visibility': true,
    });

    testWidgets('1. Displays name, formatted price, duration, and top preview features', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          SubscriptionPlanCard(
            plan: growthPlan,
            isSelected: false,
            onSelect: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Growth Plan'), findsOneWidget);
      expect(find.text('₹2,999'), findsOneWidget);
      expect(find.text(' / 30 days'), findsOneWidget);
      expect(find.text('INCLUDED FEATURES'), findsOneWidget);

      // Top 3 features are shown initially
      expect(find.text('WhatsApp Campaigns'), findsOneWidget);
      expect(find.text('Client Segmentation'), findsOneWidget);
      expect(find.text('Service-Based Targeting'), findsOneWidget);

      // 4th feature is initially hidden under expand
      expect(find.text('View all 8 features'), findsOneWidget);
    });

    testWidgets('2. Tapping expand button reveals remaining features without invoking onSelect', (tester) async {
      bool selectedCalled = false;

      await tester.pumpWidget(
        _wrapWithTheme(
          SubscriptionPlanCard(
            plan: growthPlan,
            isSelected: false,
            onSelect: () {
              selectedCalled = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "View all 8 features"
      await tester.tap(find.text('View all 8 features'));
      await tester.pumpAndSettle();

      // Expansion toggle MUST NOT trigger card onSelect
      expect(selectedCalled, isFalse);

      // After expansion, remaining features like "Priority Search Visibility" are visible
      expect(find.text('Priority Search Visibility'), findsOneWidget);
      expect(find.text('Advanced Business Insights'), findsOneWidget);
      expect(find.text('Show less'), findsOneWidget);

      // Collapse back
      await tester.tap(find.text('Show less'));
      await tester.pumpAndSettle();
      expect(find.text('View all 8 features'), findsOneWidget);
      expect(selectedCalled, isFalse);
    });

    testWidgets('3. Tapping card triggers onSelect callback', (tester) async {
      bool selectedCalled = false;

      await tester.pumpWidget(
        _wrapWithTheme(
          SubscriptionPlanCard(
            plan: growthPlan,
            isSelected: false,
            onSelect: () {
              selectedCalled = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap card body / name
      await tester.tap(find.text('Growth Plan'));
      await tester.pumpAndSettle();

      expect(selectedCalled, isTrue);
    });

    testWidgets('4. Displays CURRENT PLAN badge when isCurrentPlan is true', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          SubscriptionPlanCard(
            plan: growthPlan,
            isSelected: true,
            isCurrentPlan: true,
            onSelect: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CURRENT PLAN'), findsOneWidget);
    });

    testWidgets('5. Displays clean neutral message when plan has no optional features', (tester) async {
      final emptyPlan = SubscriptionPlan.fromJson({
        'id': 'basic-empty-1',
        'name': 'Free Baseline',
        'price': 0,
        'validity_days': 30,
      });

      await tester.pumpWidget(
        _wrapWithTheme(
          SubscriptionPlanCard(
            plan: emptyPlan,
            isSelected: false,
            onSelect: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Free Baseline Plan'), findsOneWidget);
      expect(find.text('₹0'), findsOneWidget);
      expect(
        find.text('Standard salon booking, catalog, staff, and wallet features included.'),
        findsOneWidget,
      );
      expect(find.text('View all features'), findsNothing);
    });
  });
}
