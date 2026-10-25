import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/models/subscription_plan.dart';

void main() {
  const growthKeys = [
    'period',
    'peak_hours',
    'repeat_customers',
    'areas',
    'gender_mix',
    'visit_gap',
    'staff_deep_dive',
    'recommended_combos',
    'upsell_links',
    'quiet_hour_offers',
    'slow_services',
    'win_back',
  ];

  group('SubscriptionPlan Model — Parsing and Feature Mapping', () {
    test('1. Parses a Starter plan: basic insights in, Growth features locked', () {
      final plan = SubscriptionPlan.fromJson({
        'id': '9d02029a-245f-4d32-b7e1-87a718b52a12',
        'name': 'Starter',
        'price': '1999.00',
        'validity_days': 30,
        'has_advanced_insights': false,
        'has_upsell_recommendations': 'basic',
        'has_cross_sell_recommendations': 'none',
        'is_active': true,
      });

      expect(plan.name, 'Starter');
      expect(plan.price, 1999.0);
      expect(plan.formattedPrice, '₹1,999');
      expect(plan.formattedDuration, '30 days');

      final includedKeys = plan.includedFeatures.map((f) => f.key).toList();
      expect(includedKeys, containsAll(['overview', 'revenue_trend', 'service_performance', 'staff_performance', 'retention', 'upsell', 'cross_sell']));
      for (final key in growthKeys) {
        expect(includedKeys, isNot(contains(key)));
      }

      // Every feature is listed so plans can be compared, locked ones too.
      expect(plan.allFeatures.map((f) => f.key), containsAll(growthKeys));

      expect(plan.allFeatures.firstWhere((f) => f.key == 'upsell').tierBadge, 'Basic');
      // An older plan saying "none" still gets the basic tips.
      expect(plan.allFeatures.firstWhere((f) => f.key == 'cross_sell').tierBadge, 'Basic');
    });

    test('2. Parses a Growth plan with every feature included', () {
      final plan = SubscriptionPlan.fromJson({
        'id': '9d02029a-245f-4d32-b7e1-87a718b52a13',
        'name': 'Growth',
        'price': 2999,
        'validity_days': 30,
        'has_advanced_insights': true,
        'has_upsell_recommendations': 'advanced',
        'has_cross_sell_recommendations': 'advanced',
      });

      expect(plan.formattedPrice, '₹2,999');
      expect(plan.includedFeatures.length, plan.allFeatures.length);
      expect(plan.allFeatures.firstWhere((f) => f.key == 'upsell').tierBadge, 'Full');
      expect(plan.allFeatures.firstWhere((f) => f.key == 'cross_sell').tierBadge, 'Full');
    });

    test('3. No WhatsApp marketing or priority visibility is offered on any plan', () {
      final plan = SubscriptionPlan.fromJson({
        'name': 'Old Growth',
        'whatsapp_campaign_limit': 1000,
        'has_customer_segmentation': true,
        'has_priority_visibility': true,
        'has_advanced_insights': true,
      });

      final keys = plan.allFeatures.map((f) => f.key);
      expect(keys, isNot(contains('whatsapp_campaign_limit')));
      expect(keys, isNot(contains('has_customer_segmentation')));
      expect(keys, isNot(contains('has_priority_visibility')));
    });

    test('4. Gracefully handles null, missing, or malformed data without crashing', () {
      final plan = SubscriptionPlan.fromJson(<String, dynamic>{});

      expect(plan.id, '');
      expect(plan.name, 'Plan');
      expect(plan.price, 0.0);
      expect(plan.validityDays, 30);
      expect(plan.formattedPrice, '₹0');
      expect(plan.hasUpsellRecommendations, 'none');

      // Only the basics every plan has.
      expect(plan.includedFeatures.map((f) => f.key), isNot(contains('period')));
      expect(plan.includedFeatures, isNotEmpty);
    });

    test('5. Safely handles unexpected tier strings', () {
      final plan = SubscriptionPlan.fromJson({
        'id': 'test-plan',
        'name': 'Custom Plan',
        'has_upsell_recommendations': 'EXPERIMENTAL_TIER',
        'has_cross_sell_recommendations': null,
      });

      expect(plan.hasUpsellRecommendations, 'none');
      expect(plan.hasCrossSellRecommendations, 'none');
      expect(plan.allFeatures.firstWhere((f) => f.key == 'upsell').tierBadge, 'Basic');
    });
  });
}
