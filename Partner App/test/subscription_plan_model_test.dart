import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/models/subscription_plan.dart';

void main() {
  group('SubscriptionPlan Model — Parsing and Feature Mapping', () {
    test('1. Parses real Starter plan JSON correctly', () {
      final starterJson = {
        'id': '9d02029a-245f-4d32-b7e1-87a718b52a12',
        'name': 'Starter',
        'price': '1999.00',
        'validity_days': 30,
        'whatsapp_campaign_limit': 250,
        'whatsapp_message_limit': 0,
        'has_customer_segmentation': true,
        'has_service_based_targeting': false,
        'has_high_value_targeting': false,
        'has_advanced_insights': false,
        'has_upsell_recommendations': 'basic',
        'has_cross_sell_recommendations': 'none',
        'has_priority_visibility': false,
        'is_active': true,
        'is_commission_plan': false,
      };

      final plan = SubscriptionPlan.fromJson(starterJson);

      expect(plan.id, '9d02029a-245f-4d32-b7e1-87a718b52a12');
      expect(plan.name, 'Starter');
      expect(plan.price, 1999.0);
      expect(plan.validityDays, 30);
      expect(plan.formattedPrice, '₹1,999');
      expect(plan.formattedDuration, '30 days');
      expect(plan.whatsappCampaignLimit, 250);
      expect(plan.hasCustomerSegmentation, isTrue);
      expect(plan.hasServiceBasedTargeting, isFalse);
      expect(plan.hasHighValueTargeting, isFalse);
      expect(plan.hasAdvancedInsights, isFalse);
      expect(plan.hasUpsellRecommendations, 'basic');
      expect(plan.hasCrossSellRecommendations, 'none');
      expect(plan.hasPriorityVisibility, isFalse);

      final included = plan.includedFeatures;
      final includedKeys = included.map((f) => f.key).toList();

      // Included: whatsapp_campaign_limit, has_customer_segmentation, has_upsell_recommendations
      expect(includedKeys, contains('whatsapp_campaign_limit'));
      expect(includedKeys, contains('has_customer_segmentation'));
      expect(includedKeys, contains('has_upsell_recommendations'));

      // Excluded: service_based, high_value, advanced_insights, cross_sell, priority_visibility
      expect(includedKeys, isNot(contains('has_service_based_targeting')));
      expect(includedKeys, isNot(contains('has_high_value_targeting')));
      expect(includedKeys, isNot(contains('has_advanced_insights')));
      expect(includedKeys, isNot(contains('has_cross_sell_recommendations')));
      expect(includedKeys, isNot(contains('has_priority_visibility')));

      // Campaign limit formatting
      final campaignFeature = included.firstWhere((f) => f.key == 'whatsapp_campaign_limit');
      expect(campaignFeature.formattedValue, '250 campaigns per cycle');
      expect(campaignFeature.tierBadge, '250/cycle');

      // Upsell tier formatting
      final upsellFeature = included.firstWhere((f) => f.key == 'has_upsell_recommendations');
      expect(upsellFeature.tierBadge, 'Basic');
    });

    test('2. Parses real Growth plan JSON with all features enabled', () {
      final growthJson = {
        'id': '9d02029a-245f-4d32-b7e1-87a718b52a13',
        'name': 'Growth',
        'price': 2999,
        'validity_days': 30,
        'whatsapp_campaign_limit': 1000,
        'whatsapp_message_limit': 0,
        'has_customer_segmentation': true,
        'has_service_based_targeting': true,
        'has_high_value_targeting': true,
        'has_advanced_insights': true,
        'has_upsell_recommendations': 'advanced',
        'has_cross_sell_recommendations': 'advanced',
        'has_priority_visibility': true,
        'is_active': true,
        'is_commission_plan': false,
      };

      final plan = SubscriptionPlan.fromJson(growthJson);

      expect(plan.name, 'Growth');
      expect(plan.price, 2999.0);
      expect(plan.formattedPrice, '₹2,999');

      final included = plan.includedFeatures;
      expect(included.length, 8); // All 8 features enabled

      final campaignFeature = included.firstWhere((f) => f.key == 'whatsapp_campaign_limit');
      expect(campaignFeature.formattedValue, '1,000 campaigns per cycle');

      final upsellFeature = included.firstWhere((f) => f.key == 'has_upsell_recommendations');
      expect(upsellFeature.tierBadge, 'Advanced');

      final crossSellFeature = included.firstWhere((f) => f.key == 'has_cross_sell_recommendations');
      expect(crossSellFeature.tierBadge, 'Advanced');

      final priorityFeature = included.firstWhere((f) => f.key == 'has_priority_visibility');
      expect(priorityFeature.tierBadge, 'Premium');
    });

    test('3. Handles zero campaign limit as Unlimited per backend semantics', () {
      final json = {
        'id': 'unlimited-plan',
        'name': 'VIP Unlimited',
        'price': 4999.00,
        'validity_days': 30,
        'whatsapp_campaign_limit': 0, // 0 in CampaignEntitlementService represents unlimited
      };

      final plan = SubscriptionPlan.fromJson(json);
      final campaignFeature = plan.includedFeatures.firstWhere((f) => f.key == 'whatsapp_campaign_limit');

      expect(campaignFeature.isIncluded, isTrue);
      expect(campaignFeature.tierBadge, 'Unlimited');
      expect(campaignFeature.formattedValue, 'Unlimited campaigns per cycle');
    });

    test('4. Gracefully handles null, missing, or malformed data without crashing', () {
      final legacyEmptyJson = <String, dynamic>{};

      final plan = SubscriptionPlan.fromJson(legacyEmptyJson);

      expect(plan.id, '');
      expect(plan.name, 'Plan');
      expect(plan.price, 0.0);
      expect(plan.validityDays, 30);
      expect(plan.formattedPrice, '₹0');
      expect(plan.formattedDuration, '30 days');
      expect(plan.whatsappCampaignLimit, isNull);
      expect(plan.hasCustomerSegmentation, isFalse);
      expect(plan.hasUpsellRecommendations, 'none');
      expect(plan.hasCrossSellRecommendations, 'none');

      // No features included
      expect(plan.includedFeatures, isEmpty);
    });

    test('5. Safely handles unexpected tier strings', () {
      final weirdJson = {
        'id': 'test-plan',
        'name': 'Custom Plan',
        'has_upsell_recommendations': 'EXPERIMENTAL_TIER',
        'has_cross_sell_recommendations': null,
      };

      final plan = SubscriptionPlan.fromJson(weirdJson);

      expect(plan.hasUpsellRecommendations, 'none');
      expect(plan.hasCrossSellRecommendations, 'none');
      expect(plan.includedFeatures.any((f) => f.key == 'has_upsell_recommendations'), isFalse);
    });
  });
}
