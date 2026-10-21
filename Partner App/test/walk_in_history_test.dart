import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/screens/walk_in_history_screen.dart';
import 'package:partner_app/screens/walk_in_screen.dart';
import 'package:partner_app/services/walk_in_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WalkInHistory Models JSON Serialization', () {
    test('WalkInHistoryResponse parses correctly from backend response format', () {
      final json = {
        'summary': {
          'total_walk_ins': 15,
          'today_walk_ins': 4,
          'in_progress': 2,
          'completed': 12,
          'total_revenue': 6500.50,
        },
        'walk_ins': [
          {
            'id': 'apt-uuid-1',
            'status': 'completed',
            'booking_source': 'walk_in',
            'appointment_date': '2026-10-21',
            'start_time': '11:00:00',
            'end_time': '11:45:00',
            'started_at': '2026-10-21T11:00:00Z',
            'completed_at': '2026-10-21T11:45:00Z',
            'customer_name': 'Ramesh Kumar',
            'customer_phone': '9876543210',
            'customer_gender': 'Male',
            'appointed_provider': {
              'id': 'prov-1',
              'name': 'Stylist John',
              'phone': '9998887776',
            },
            'serving_provider': {
              'id': 'prov-1',
              'name': 'Stylist John',
              'phone': '9998887776',
            },
            'services': [
              {
                'id': 'line-1',
                'service_id': 'srv-1',
                'name': 'Classic Haircut',
                'category': 'Hair Care',
                'price': 400.0,
                'duration_minutes': 30,
                'serving_provider_name': 'Stylist John',
                'line_status': 'completed',
              }
            ],
            'service_additions': [
              {
                'id': 'add-1',
                'service_id': 'srv-extra',
                'name': 'Beard Trim',
                'price': 150.0,
                'duration_minutes': 15,
                'provider_name': 'Stylist John',
                'added_by_name': 'Desk Manager',
                'status': 'completed',
                'added_at': '2026-10-21T11:20:00Z',
              }
            ],
            'total_amount': 550.0,
            'advance_amount': 0.0,
            'balance_amount': 0.0,
            'final_billed_amount': 550.0,
            'payment_mode': 'upi',
            'payment_collected_at': '2026-10-21T11:45:00Z',
            'payment_collected_by_name': 'Owner Dave',
            'verification_method': 'manual',
            'invoice_id': 'inv-123',
            'invoice_number': 'INV-2026-0001',
          }
        ],
        'pagination': {
          'current_page': 1,
          'last_page': 1,
          'per_page': 50,
          'total': 1,
        },
        'viewer': {
          'role': 'admin',
          'provider_id': null,
        },
      };

      final response = WalkInHistoryResponse.fromJson(json);

      expect(response.summary.totalWalkIns, 15);
      expect(response.summary.todayWalkIns, 4);
      expect(response.summary.inProgress, 2);
      expect(response.summary.completed, 12);
      expect(response.summary.totalRevenue, 6500.50);

      expect(response.walkIns.length, 1);
      final item = response.walkIns.first;
      expect(item.id, 'apt-uuid-1');
      expect(item.customerName, 'Ramesh Kumar');
      expect(item.customerPhone, '9876543210');
      expect(item.customerGender, 'Male');
      expect(item.isCompleted, true);
      expect(item.isInProgress, false);
      expect(item.paymentMode, 'upi');
      expect(item.paymentCollectedByName, 'Owner Dave');
      expect(item.services.length, 1);
      expect(item.services.first.name, 'Classic Haircut');
      expect(item.serviceAdditions.length, 1);
      expect(item.serviceAdditions.first.name, 'Beard Trim');
      expect(item.displayAmount, 550.0);
    });
  });

  group('WalkInHistoryScreen Widget Tests', () {
    testWidgets('WalkInHistoryScreen renders header, summary metrics, and search bar', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: WalkInHistoryScreen(salonId: 'salon-123', salonName: 'Elite Parlour'),
        ),
      );

      // Verify header texts
      expect(find.text('Walk-in History'), findsOneWidget);
      expect(find.text('Elite Parlour'), findsOneWidget);

      // Verify metric labels
      expect(find.text('Total Walk-ins'), findsOneWidget);
      expect(find.text('Today'), findsNWidgets(2)); // Metric card & filter chip
      expect(find.text('In Progress'), findsNWidgets(2)); // Metric card & filter chip
      expect(find.text('Revenue'), findsOneWidget);

      // Verify filter labels
      expect(find.text('All Time'), findsOneWidget);
      expect(find.text('All Statuses'), findsOneWidget);
    });
  });

  group('WalkInScreen History Button Tests', () {
    testWidgets('Embedded WalkInScreen shows "History" button in top header row', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: WalkInScreen(salonId: 'salon-123', embedded: true),
        ),
      );

      // Let options load attempt settle
      await tester.pump();

      // Check header and History button
      expect(find.text('Add walk-in customer'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.byIcon(Icons.history_rounded), findsOneWidget);
    });

    testWidgets('Standalone WalkInScreen shows "History" button in AppBar actions', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: WalkInScreen(salonId: 'salon-123', embedded: false),
        ),
      );

      await tester.pump();

      expect(find.text('Add walk-in'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.byIcon(Icons.history_rounded), findsOneWidget);
    });
  });
}
