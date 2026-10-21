import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/models/admin_provider_models.dart';
import 'package:partner_app/models/service_models.dart';
import 'package:partner_app/models/staff_models.dart';
import 'package:partner_app/screens/dashboard/tabs/services_tab.dart';
import 'package:partner_app/screens/dashboard/tabs/staff_tab.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/widgets/unassigned_services_warning_banner.dart';
import 'package:partner_app/widgets/assign_service_staff_sheet.dart';

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
      expect(find.text('Assign to Staff'), findsOneWidget);
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
      expect(find.text('Assign to Staff'), findsOneWidget);
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

  group('AssignServiceStaffSheet Modal Tests', () {
    final sampleStaff = [
      {
        'id': 'provider-1',
        'user_id': 'user-1',
        'specialization': 'Senior Stylist',
        'is_admin_provider': false,
        'user': {'name': 'Rohan Sharma', 'role': 'service_provider'},
      },
      {
        'id': 'provider-2',
        'user_id': 'user-2',
        'specialization': 'Color Specialist',
        'is_admin_provider': false,
        'user': {'name': 'Priya Patel', 'role': 'service_provider'},
      },
      {
        'id': 'provider-admin',
        'user_id': 'user-admin',
        'specialization': 'Owner & Specialist',
        'is_admin_provider': true,
        'user': {'name': 'Salon Admin', 'role': 'admin'},
      },
    ];

    testWidgets('renders service name, providers list and admin provider badge', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AssignServiceStaffSheet(
            salonId: 'test-salon-id',
            serviceId: 'srv-1',
            serviceName: 'Hair Spa Detox',
            unassignedServices: sampleUnassigned,
            initialStaff: sampleStaff,
            initialAssignedStaffIds: const {},
          ),
        ),
      ));

      expect(find.text('Assign to Staff'), findsWidgets);
      expect(find.text('Hair Spa Detox'), findsWidgets);
      expect(find.text('Rohan Sharma'), findsOneWidget);
      expect(find.text('Senior Stylist'), findsOneWidget);
      expect(find.text('Priya Patel'), findsOneWidget);
      expect(find.text('Salon Admin'), findsOneWidget);
      expect(find.text('Admin (Provider)'), findsOneWidget);
      expect(find.text('Providers (0/3 selected)'), findsOneWidget);
    });

    testWidgets('allows selecting single or multiple providers and toggles Select All', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AssignServiceStaffSheet(
            salonId: 'test-salon-id',
            serviceId: 'srv-1',
            serviceName: 'Hair Spa Detox',
            unassignedServices: sampleUnassigned,
            initialStaff: sampleStaff,
            initialAssignedStaffIds: const {},
          ),
        ),
      ));

      // 1. Tap on Rohan Sharma tile
      await tester.tap(find.text('Rohan Sharma'));
      await tester.pumpAndSettle();

      expect(find.text('Providers (1/3 selected)'), findsOneWidget);
      expect(find.text('Assign (1 Staff)'), findsOneWidget);

      // 2. Tap on Salon Admin (Admin provider) tile
      await tester.tap(find.text('Salon Admin'));
      await tester.pumpAndSettle();

      expect(find.text('Providers (2/3 selected)'), findsOneWidget);
      expect(find.text('Assign (2 Staff)'), findsOneWidget);

      // 3. Tap Select All
      await tester.tap(find.text('Select All'));
      await tester.pumpAndSettle();

      expect(find.text('Providers (3/3 selected)'), findsOneWidget);
      expect(find.text('Deselect All'), findsOneWidget);
      expect(find.text('Assign (3 Staff)'), findsOneWidget);

      // 4. Tap Deselect All
      await tester.tap(find.text('Deselect All'));
      await tester.pumpAndSettle();

      expect(find.text('Providers (0/3 selected)'), findsOneWidget);
      expect(find.text('Select All'), findsOneWidget);
    });

    testWidgets('shows multiple unassigned service chips switcher', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AssignServiceStaffSheet(
            salonId: 'test-salon-id',
            serviceId: 'srv-1',
            serviceName: 'Hair Spa Detox',
            unassignedServices: sampleUnassigned,
            initialStaff: sampleStaff,
            initialAssignedStaffIds: const {},
          ),
        ),
      ));

      expect(find.text('Hair Spa Detox'), findsWidgets);
      expect(find.text('Beard Styling'), findsOneWidget);
      expect(find.text('Keratin Gloss'), findsOneWidget);
      expect(find.text('Charcoal Facial'), findsOneWidget);
    });
  });
}
