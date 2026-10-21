import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/models/admin_provider_models.dart';
import 'package:partner_app/models/service_models.dart';
import 'package:partner_app/models/staff_models.dart';
import 'package:partner_app/screens/dashboard/tabs/services_tab.dart';
import 'package:partner_app/screens/dashboard/tabs/staff_tab.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/widgets/unassigned_services_warning_banner.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: child),
  );
}

void main() {
  final sampleUnassigned = [
    UnassignedServiceItem(
      id: 'srv-1',
      name: 'Hair Spa Detox',
      categoryName: 'Hair Care',
      price: 1500,
      durationMinutes: 60,
    ),
    UnassignedServiceItem(
      id: 'srv-2',
      name: 'Beard Styling',
      categoryName: 'Beard Care',
      price: 350,
      durationMinutes: 30,
    ),
    UnassignedServiceItem(
      id: 'srv-3',
      name: 'Keratin Gloss',
      categoryName: 'Hair Care',
      price: 3200,
      durationMinutes: 90,
    ),
    UnassignedServiceItem(
      id: 'srv-4',
      name: 'Charcoal Facial',
      categoryName: 'Skin Care',
      price: 1800,
      durationMinutes: 45,
    ),
  ];

  group('UnassignedServicesWarningBanner Widget Tests', () {
    testWidgets('renders nothing when unassigned services list is empty', (tester) async {
      await tester.pumpWidget(_wrap(
        const UnassignedServicesWarningBanner(unassignedServices: []),
      ));

      expect(find.byType(UnassignedServicesWarningBanner), findsOneWidget);
      expect(find.textContaining('Not Assigned to Staff'), findsNothing);
    });

    testWidgets('renders warning title, count and service chips when services exist', (tester) async {
      await tester.pumpWidget(_wrap(
        UnassignedServicesWarningBanner(
          unassignedServices: sampleUnassigned,
        ),
      ));

      expect(find.text('4 Services Not Assigned to Staff'), findsOneWidget);
      expect(find.text('Hair Spa Detox'), findsOneWidget);
      expect(find.text('Beard Styling'), findsOneWidget);
      expect(find.text('Keratin Gloss'), findsOneWidget);
      // Since sample has 4, "+1 more" should be visible initially
      expect(find.text('+1 more'), findsOneWidget);
      expect(find.text('Charcoal Facial'), findsNothing);

      // Tap "+1 more" to expand
      await tester.tap(find.text('+1 more'));
      await tester.pumpAndSettle();

      expect(find.text('Charcoal Facial'), findsOneWidget);
      expect(find.text('Show less'), findsOneWidget);
    });

    testWidgets('action button triggers onActionPressed callback', (tester) async {
      bool actionPressed = false;

      await tester.pumpWidget(_wrap(
        UnassignedServicesWarningBanner(
          unassignedServices: sampleUnassigned,
          actionLabel: 'Assign Now',
          onActionPressed: () {
            actionPressed = true;
          },
        ),
      ));

      expect(find.text('Assign Now'), findsOneWidget);
      await tester.tap(find.text('Assign Now'));
      await tester.pump();

      expect(actionPressed, isTrue);
    });

    testWidgets('tapping service chip triggers onServicePressed callback', (tester) async {
      UnassignedServiceItem? pressedItem;

      await tester.pumpWidget(_wrap(
        UnassignedServicesWarningBanner(
          unassignedServices: sampleUnassigned,
          onServicePressed: (item) {
            pressedItem = item;
          },
        ),
      ));

      await tester.tap(find.text('Hair Spa Detox'));
      await tester.pump();

      expect(pressedItem, isNotNull);
      expect(pressedItem!.id, equals('srv-1'));
    });
  });

  group('StaffTab Unassigned Services Warning Tests', () {
    testWidgets('displays warning banner when unassigned services are present', (tester) async {
      final key = GlobalKey<StaffTabState>();

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: StaffTab(key: key, salonId: 'test-salon-id'),
      ));

      key.currentState?.setTestData(
        staff: [
          StaffMember(
            id: 'staff-1',
            userId: 'user-1',
            salonId: 'test-salon-id',
            isActive: true,
            isAdminProvider: false,
            specialization: 'Stylist',
            baseSalary: 25000,
            commissionPercentage: 10,
            user: {'name': 'Rohan Sharma', 'phone': '9876543210'},
          )
        ],
        leaves: [],
        adminStatus: AdminProviderStatus(
          isProviderEnabled: false,
          provider: null,
          setupValidation: AdminProviderValidation(
            salonHoursConfigured: true,
            adminHoursConfigured: false,
            servicesAssigned: false,
            isReadyForBooking: false,
          ),
          upcomingAppointmentsCount: 0,
        ),
        unassignedServices: [
          sampleUnassigned[0],
          sampleUnassigned[1],
        ],
      );

      await tester.pumpAndSettle();

      expect(find.text('2 Services Not Assigned to Staff'), findsOneWidget);
      expect(find.text('Hair Spa Detox'), findsOneWidget);
      expect(find.text('Beard Styling'), findsOneWidget);
      expect(find.text('Assign to Admin'), findsOneWidget);
    });

    testWidgets('hides warning banner when all services are assigned', (tester) async {
      final key = GlobalKey<StaffTabState>();

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: StaffTab(key: key, salonId: 'test-salon-id'),
      ));

      key.currentState?.setTestData(
        staff: [],
        leaves: [],
        unassignedServices: [],
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('Not Assigned to Staff'), findsNothing);
    });
  });

  group('ServicesTab Unassigned Services Warning Tests', () {
    testWidgets('displays warning banner in services tab when services are unassigned', (tester) async {
      final key = GlobalKey<ServicesTabState>();

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: ServicesTab(key: key, salonId: 'test-salon-id'),
      ));

      key.currentState?.setTestData(
        groupedServices: [
          {
            'category': {'id': 'cat-1', 'name': 'Hair Care', 'is_custom': false},
            'services': [
              {
                'id': 'srv-1',
                'salon_id': 'test-salon-id',
                'template_id': 'tmpl-1',
                'price': '1500',
                'template': {
                  'id': 'tmpl-1',
                  'category_id': 'cat-1',
                  'name': 'Hair Spa Detox',
                  'estimated_duration_minutes': 60,
                  'is_custom': false,
                }
              }
            ]
          }
        ],
        combos: [],
        unassignedServices: [sampleUnassigned[0]],
      );

      await tester.pumpAndSettle();

      expect(find.text('1 Service Not Assigned to Staff'), findsOneWidget);
      expect(find.text('Hair Spa Detox'), findsWidgets);
      expect(find.text('Assign Staff'), findsOneWidget);
    });

    testWidgets('hides warning banner in services tab when all services are covered', (tester) async {
      final key = GlobalKey<ServicesTabState>();

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: ServicesTab(key: key, salonId: 'test-salon-id'),
      ));

      key.currentState?.setTestData(
        groupedServices: [],
        combos: [],
        unassignedServices: [],
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('Not Assigned to Staff'), findsNothing);
    });
  });
}
