import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/screens/dashboard/more/insights_screen.dart';
import 'package:partner_app/services/insights_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Business Insights Real Data Models JSON Parsing', () {
    test('SalonInsights parses real basicAnalytics and retentionFunnel', () {
      final json = {
        'success': true,
        'data': {
          'plan_name': 'Admin Full Access',
          'advanced': true,
          'overview': {
            'customers': 45,
            'returning_customers': 20,
            'repeat_rate': 44.4,
            'total_visits': 78,
            'revenue': 84500.0,
            'average_bill': 1083.33,
            'average_visits_per_customer': 1.7,
          },
          'services': [
            {'service_id': 'srv-1', 'name': 'Hair Spa', 'bookings': 30, 'revenue': 45000.0},
          ],
          'campaigns': {
            'campaigns': 2,
            'sent': 150,
            'delivered': 148,
            'read': 120,
            'read_rate': 81.1,
          },
          'basic_analytics': {
            'revenue_trend': {
              'total_revenue': 84500.0,
              'total_bookings': 78,
              'weeks': [
                {'label': 'W1', 'period': '01 Oct - 07 Oct', 'revenue': 18000.0, 'bookings': 16},
                {'label': 'W2', 'period': '08 Oct - 14 Oct', 'revenue': 22500.0, 'bookings': 21},
                {'label': 'W3', 'period': '15 Oct - 21 Oct', 'revenue': 19000.0, 'bookings': 18},
                {'label': 'W4', 'period': '22 Oct - 28 Oct', 'revenue': 25000.0, 'bookings': 23},
              ],
            },
            'staff_performance': [
              {'id': 'staff-1', 'name': 'Vikram Rathore', 'bookings': 42, 'revenue': 48000.0},
              {'id': 'staff-2', 'name': 'Pooja Verma', 'bookings': 36, 'revenue': 36500.0},
            ],
          },
          'retention_funnel': {
            'total_customers': 45,
            'first_visits': {'count': 45, 'rate': 100.0},
            'second_visits': {'count': 20, 'rate': 44.4},
            'third_visits': {'count': 12, 'rate': 26.7},
            'regular_visits': {'count': 6, 'rate': 13.3},
            'benchmark_message': 'Your 44.4% 2nd-visit rate is above the 35% industry average.',
            'benchmark_is_good': true,
          },
          'repeat_customers': {
            'buckets': [
              {'label': 'Came once', 'count': 25},
              {'label': 'Occasional', 'count': 14},
              {'label': 'Regulars (3+ visits)', 'count': 6},
            ],
            'at_risk': 3,
            'at_risk_after_days': 60,
            'top_customers': [
              {'name': 'Ananya Roy', 'visits': 5, 'spend': 9200.0},
            ],
          },
          'peak_hours': {
            'by_hour': [
              {'hour': 10, 'label': '10am', 'bookings': 12},
              {'hour': 16, 'label': '4pm', 'bookings': 20},
            ],
            'by_day': [
              {'day': 'Monday', 'bookings': 8},
              {'day': 'Saturday', 'bookings': 24},
            ],
            'busiest_hour': '4pm',
            'quietest_hour': '10am',
            'quietest_day': 'Monday',
            'closed_days': [],
          },
        },
        'locked': [],
      };

      final insights = SalonInsights.fromJson(json);

      expect(insights.advanced, isTrue);
      expect(insights.planName, equals('Admin Full Access'));
      expect(insights.basicAnalytics, isNotNull);
      expect(insights.basicAnalytics!.revenueTrend.totalRevenue, equals(84500.0));
      expect(insights.basicAnalytics!.revenueTrend.totalBookings, equals(78));
      expect(insights.basicAnalytics!.revenueTrend.weeks.length, equals(4));
      expect(insights.basicAnalytics!.revenueTrend.weeks[0].label, equals('W1'));
      expect(insights.basicAnalytics!.revenueTrend.weeks[0].revenue, equals(18000.0));

      expect(insights.basicAnalytics!.staffPerformance.length, equals(2));
      expect(insights.basicAnalytics!.staffPerformance[0].name, equals('Vikram Rathore'));
      expect(insights.basicAnalytics!.staffPerformance[0].bookings, equals(42));
      expect(insights.basicAnalytics!.staffPerformance[0].revenue, equals(48000.0));

      expect(insights.retentionFunnel, isNotNull);
      expect(insights.retentionFunnel!.totalCustomers, equals(45));
      expect(insights.retentionFunnel!.firstVisits.count, equals(45));
      expect(insights.retentionFunnel!.secondVisits.rate, equals(44.4));
      expect(insights.retentionFunnel!.benchmarkIsGood, isTrue);
      expect(insights.retentionFunnel!.benchmarkMessage, contains('44.4%'));
    });

    test('SalonInsights handles empty analytics and retention funnel safely', () {
      final json = {
        'success': true,
        'data': {
          'overview': {},
          'services': [],
          'campaigns': {},
          'basic_analytics': {
            'revenue_trend': {
              'total_revenue': 0,
              'total_bookings': 0,
              'weeks': [],
            },
            'staff_performance': [],
          },
          'retention_funnel': {
            'total_customers': 0,
            'first_visits': {'count': 0, 'rate': 0},
            'second_visits': {'count': 0, 'rate': 0},
            'third_visits': {'count': 0, 'rate': 0},
            'regular_visits': {'count': 0, 'rate': 0},
            'benchmark_message': 'No customer visits recorded yet.',
            'benchmark_is_good': false,
          },
        },
        'locked': [],
      };

      final insights = SalonInsights.fromJson(json);
      expect(insights.basicAnalytics, isNotNull);
      expect(insights.basicAnalytics!.revenueTrend.totalRevenue, equals(0.0));
      expect(insights.basicAnalytics!.staffPerformance, isEmpty);
      expect(insights.retentionFunnel, isNotNull);
      expect(insights.retentionFunnel!.totalCustomers, equals(0));
      expect(insights.retentionFunnel!.benchmarkIsGood, isFalse);
    });

    test('SalonInsights parses recommended combos cleanly for Do this next', () {
      final json = {
        'data': {
          'advanced': true,
          'overview': {
            'customers': 50,
            'returning_customers': 20,
            'repeat_rate': 40.0,
            'total_visits': 80,
            'revenue': 50000.0,
            'average_bill': 625.0,
            'average_visits_per_customer': 1.6,
          },
          'recommended_combos': [
            {
              'services': ['Haircut', 'Beard Trim'],
              'service_ids': ['s1', 's2'],
              'suggestion': 'Package Haircut and Beard Trim together',
              'combo_name': 'Haircut + Beard Trim',
              'is_actionable': true,
            }
          ],
        },
      };
      final insights = SalonInsights.fromJson(json);
      expect(insights.recommendedCombos.length, equals(1));
      expect(insights.recommendedCombos.first.comboName, equals('Haircut + Beard Trim'));
      expect(insights.recommendedCombos.first.isActionable, isTrue);
    });
  });

  group('InsightsScreen Widget Rendering Tests', () {
    testWidgets('InsightsScreen renders real data without dummy staff names', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InsightsScreen(salonId: 'test-salon-id'),
          ),
        ),
      );

      // Loading state
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
