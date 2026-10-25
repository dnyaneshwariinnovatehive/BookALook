import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/screens/dashboard/more/insights_screen.dart';
import 'package:partner_app/services/insights_api.dart';

Map<String, dynamic> _base() => {
      'overview': {'customers': 4, 'revenue': 2200, 'repeat_rate': 25, 'total_visits': 4, 'average_bill': 550},
      'services': [
        {'service_id': 's1', 'name': 'Haircut', 'bookings': 4, 'revenue': 2200},
      ],
      'basic_analytics': {
        'revenue_trend': {'total_revenue': 400, 'total_bookings': 1, 'weeks': []},
        'staff_performance': [],
      },
      'upsell': [
        {'from': 'Haircut', 'to': 'Hair Spa', 'evidence': 3},
      ],
    };

void main() {
  Future<void> pump(WidgetTester tester, SalonInsights insights, List<int> requested) async {
    await tester.binding.setSurfaceSize(const Size(500, 4000));
    await tester.pumpWidget(MaterialApp(
      home: InsightsScreen(
        salonId: 's1',
        load: (days) async {
          requested.add(days);
          return insights;
        },
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Starter sees its basics, Growth sections locked, and an upgrade button', (tester) async {
    final insights = SalonInsights.fromJson({
      'data': {..._base(), 'plan_name': 'Starter', 'advanced': false, 'periods': [30]},
      'locked': [
        {'key': 'period', 'name': 'Longer history', 'reason': 'Compare 30, 90 and 365 days.'},
        {'key': 'win_back', 'name': 'Win-back list', 'reason': 'Regulars who stopped coming.'},
        {'key': 'upsell_advanced', 'name': 'Full upsell tips', 'reason': 'Every trade-up.'},
      ],
    });

    await pump(tester, insights, []);

    expect(find.text('Haircut  →  Hair Spa'), findsOneWidget);
    // Basic tips carry no rupee figure.
    expect(find.textContaining('+₹'), findsNothing);
    expect(find.byKey(const ValueKey('locked_period')), findsOneWidget);
    expect(find.byKey(const ValueKey('locked_win_back')), findsOneWidget);
    expect(find.byKey(const ValueKey('insights_upgrade')), findsOneWidget);
    expect(find.byKey(const ValueKey('insights_period_90')), findsNothing);
  });

  testWidgets('Growth sees the period picker, win-back list and no locks', (tester) async {
    final requested = <int>[];
    final insights = SalonInsights.fromJson({
      'data': {
        ..._base(),
        'plan_name': 'Growth',
        'advanced': true,
        'periods': [30, 90, 365],
        'upsell': [
          {'from': 'Haircut', 'to': 'Hair Spa', 'uplift': 700, 'evidence': 3},
        ],
        'period': {
          'days': 30,
          'metrics': {
            'revenue': {'current': 2200, 'previous': 1100, 'change_percent': 100},
            'visits': {'current': 4, 'previous': 2, 'change_percent': 100},
            'customers': {'current': 2, 'previous': 0, 'change_percent': null},
            'average_bill': {'current': 550, 'previous': 550, 'change_percent': 0},
          },
        },
        'win_back': [
          {'name': 'Meera', 'phone': '9811100000', 'visits': 3, 'spend': 1800, 'days_since': 100},
        ],
      },
      'locked': [],
    });

    await pump(tester, insights, requested);

    expect(find.byKey(const ValueKey('insights_period_90')), findsOneWidget);
    expect(find.text('Meera'), findsOneWidget);
    expect(find.text('+₹700'), findsOneWidget);
    expect(find.byKey(const ValueKey('insights_upgrade')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('insights_period_90')));
    await tester.pumpAndSettle();
    expect(requested, [30, 90]);
  });
}
