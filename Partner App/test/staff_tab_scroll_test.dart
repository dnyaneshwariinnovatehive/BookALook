import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/models/admin_provider_models.dart';
import 'package:partner_app/models/leave_models.dart';
import 'package:partner_app/models/staff_models.dart';
import 'package:partner_app/screens/dashboard/tabs/staff_tab.dart';
import 'package:partner_app/theme/app_theme.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: child,
  );
}

void main() {
  final sampleStaff = [
    StaffMember(
      id: 'staff-1',
      userId: 'user-1',
      salonId: 'test-salon-id',
      isActive: true,
      isAdminProvider: false,
      specialization: 'Hair & Colour',
      baseSalary: 25000,
      commissionPercentage: 10,
      user: {'name': 'Priya Salunkhe', 'phone': '9876543210'},
    ),
    StaffMember(
      id: 'staff-2',
      userId: 'user-2',
      salonId: 'test-salon-id',
      isActive: false,
      isAdminProvider: false,
      specialization: 'Spa & Massage',
      baseSalary: 22000,
      commissionPercentage: 8,
      user: {'name': 'Sameer Dixit', 'phone': '9876543211'},
    ),
    StaffMember(
      id: 'staff-3',
      userId: 'user-3',
      salonId: 'test-salon-id',
      isActive: true,
      isAdminProvider: false,
      specialization: 'Nail Artist',
      baseSalary: 18000,
      commissionPercentage: 5,
      user: {'name': 'Anjali Gupta', 'phone': '9876543212'},
    ),
    StaffMember(
      id: 'staff-4',
      userId: 'user-4',
      salonId: 'test-salon-id',
      isActive: true,
      isAdminProvider: false,
      specialization: 'Beard Stylist',
      baseSalary: 20000,
      commissionPercentage: 10,
      user: {'name': 'Rohan Patil', 'phone': '9876543213'},
    ),
  ];

  final sampleLeaves = [
    ProviderLeave(
      id: 'leave-1',
      providerId: 'staff-1',
      leaveDate: '2026-10-25',
      leaveType: 'paid',
      isFullDay: true,
      status: 'pending',
      reason: 'Personal emergency',
      provider: {
        'name': 'Priya Salunkhe',
        'user': {'name': 'Priya Salunkhe'},
      },
    ),
  ];

  final sampleAdminStatus = AdminProviderStatus(
    isProviderEnabled: true,
    provider: AdminProviderProfile(
      id: 'admin-prov-1',
      userId: 'admin-user-1',
      salonId: 'test-salon-id',
      specialization: 'Owner & Specialist',
      isActive: true,
      autoApproveLeave: true,
      servicesCount: 1,
      services: [
        AdminAssignedService(id: 's1', name: 'Signature Haircut', price: 600),
      ],
      workingHours: [],
    ),
    setupValidation: AdminProviderValidation(
      salonHoursConfigured: true,
      adminHoursConfigured: true,
      servicesAssigned: true,
      isReadyForBooking: true,
    ),
    upcomingAppointmentsCount: 0,
  );

  testWidgets('StaffTab renders NestedScrollView layout with header, provider card, and staff list', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final staffKey = GlobalKey<StaffTabState>();

    await tester.pumpWidget(
      _wrap(
        StaffTab(
          key: staffKey,
          salonId: 'test-salon-id',
        ),
      ),
    );

    // Initial mounting
    expect(find.text('Staff'), findsOneWidget);
    expect(find.byType(NestedScrollView), findsOneWidget);

    // Inject test data
    staffKey.currentState!.setTestData(
      staff: sampleStaff,
      leaves: sampleLeaves,
      adminStatus: sampleAdminStatus,
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Summary cards are present
    expect(find.text('Total Staff'), findsOneWidget);
    expect(find.text('Active'), findsWidgets); // Summary card and filter chip
    expect(find.text('On Leave'), findsOneWidget);

    // TabBar capsules are present
    expect(find.text('All Staff (4)'), findsOneWidget);
    expect(find.text('Leave Requests (1)'), findsOneWidget);

    // Provider Mode card is present
    expect(find.text('Also work as a service provider'), findsOneWidget);
    expect(find.text('Ready for Bookings'), findsOneWidget);
    expect(find.text('Configure Services & Schedule'), findsOneWidget);

    // Initial visible staff
    expect(find.text('Priya Salunkhe'), findsOneWidget);
    expect(find.text('Sameer Dixit'), findsOneWidget);
  });

  testWidgets('Scrolling down smoothly moves upper content upward to expand staff list area', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final staffKey = GlobalKey<StaffTabState>();

    await tester.pumpWidget(
      _wrap(
        StaffTab(
          key: staffKey,
          salonId: 'test-salon-id',
        ),
      ),
    );

    staffKey.currentState!.setTestData(
      staff: sampleStaff,
      leaves: sampleLeaves,
      adminStatus: sampleAdminStatus,
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Get initial position of the first staff card
    final initialStaffPos = tester.getTopLeft(find.text('Priya Salunkhe'));

    // Drag the scroll view up by 300 pixels
    await tester.drag(find.text('Priya Salunkhe'), const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 100));

    // Verify the staff card has moved upward, expanding visible list space
    final scrolledStaffPos = tester.getTopLeft(find.text('Priya Salunkhe'));
    expect(scrolledStaffPos.dy, lessThan(initialStaffPos.dy));

    // Rohan Patil (#4) should now be visible on screen after scrolling
    expect(find.text('Rohan Patil'), findsOneWidget);
  });

  testWidgets('Staff filter chip filters list correctly', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final staffKey = GlobalKey<StaffTabState>();

    await tester.pumpWidget(
      _wrap(
        StaffTab(
          key: staffKey,
          salonId: 'test-salon-id',
        ),
      ),
    );

    staffKey.currentState!.setTestData(
      staff: sampleStaff,
      leaves: sampleLeaves,
      adminStatus: sampleAdminStatus,
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Both Priya (active) and Sameer (inactive) are initially visible in 'all' filter
    expect(find.text('Priya Salunkhe'), findsOneWidget);
    expect(find.text('Sameer Dixit'), findsOneWidget);

    // Tap the 'Active' summary card or filter chip
    final activeInkWells = find.widgetWithText(InkWell, 'Active');
    await tester.tap(activeInkWells.first);
    await tester.pump(const Duration(milliseconds: 100));

    // Inactive staff member Sameer Dixit should now be hidden
    expect(find.text('Sameer Dixit'), findsNothing);
    expect(find.text('Priya Salunkhe'), findsOneWidget);
  });

  testWidgets('Summary card taps switch filters and tabs', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final staffKey = GlobalKey<StaffTabState>();

    await tester.pumpWidget(
      _wrap(
        StaffTab(
          key: staffKey,
          salonId: 'test-salon-id',
        ),
      ),
    );

    staffKey.currentState!.setTestData(
      staff: sampleStaff,
      leaves: sampleLeaves,
      adminStatus: sampleAdminStatus,
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Tap "On Leave" summary card
    await tester.tap(find.text('On Leave'));
    await tester.pumpAndSettle();

    // Should switch to Leave Requests view
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Rejected'), findsOneWidget);
  });
}
