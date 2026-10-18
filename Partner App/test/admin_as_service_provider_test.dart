import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/models/admin_provider_models.dart';
import 'package:partner_app/models/staff_models.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/screens/dashboard/tabs/staff/admin_provider_config_sheet.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: child),
  );
}

void main() {
  group('AdminProvider Models & Parsing Tests', () {
    test('Correctly parses enabled provider status with validation and profile', () {
      final json = {
        'is_provider_enabled': true,
        'provider': {
          'id': 'prov-uuid-123',
          'user_id': 'user-uuid-admin',
          'salon_id': 'salon-uuid-1',
          'specialization': 'Master Stylist & Barber',
          'is_active': true,
          'auto_approve_leave': true,
          'services_count': 2,
          'services': [
            {'id': 'svc-1', 'name': 'Classic Haircut', 'price': 350.0},
            {'id': 'svc-2', 'name': 'Beard Grooming', 'price': 200.0},
          ],
          'working_hours': [
            {
              'day_of_week': 1,
              'is_working': true,
              'start_time': '09:00:00',
              'end_time': '20:00:00',
            }
          ],
        },
        'setup_validation': {
          'salon_hours_configured': true,
          'admin_hours_configured': true,
          'services_assigned': true,
          'is_ready_for_booking': true,
        },
        'upcoming_appointments_count': 3,
      };

      final status = AdminProviderStatus.fromJson(json);

      expect(status.isProviderEnabled, isTrue);
      expect(status.provider, isNotNull);
      expect(status.provider!.id, 'prov-uuid-123');
      expect(status.provider!.specialization, 'Master Stylist & Barber');
      expect(status.upcomingAppointmentsCount, 3);
      expect(status.setupValidation.isReadyForBooking, isTrue);
      expect(status.setupValidation.salonHoursConfigured, isTrue);
      expect(status.setupValidation.adminHoursConfigured, isTrue);
      expect(status.setupValidation.servicesAssigned, isTrue);
      expect(status.provider!.services.length, 2);
      expect(status.provider!.services.first.name, 'Classic Haircut');
    });

    test('Correctly identifies incomplete setup when services and hours are missing', () {
      final json = {
        'is_provider_enabled': true,
        'provider': {
          'id': 'prov-uuid-456',
          'user_id': 'user-uuid-admin',
          'salon_id': 'salon-uuid-1',
          'specialization': null,
          'is_active': true,
          'auto_approve_leave': true,
          'services_count': 0,
          'services': <Map<String, dynamic>>[],
          'working_hours': <Map<String, dynamic>>[],
        },
        'setup_validation': {
          'salon_hours_configured': false,
          'admin_hours_configured': false,
          'services_assigned': false,
          'is_ready_for_booking': false,
        },
        'upcoming_appointments_count': 0,
      };

      final status = AdminProviderStatus.fromJson(json);

      expect(status.isProviderEnabled, isTrue);
      expect(status.setupValidation.isReadyForBooking, isFalse);
      expect(status.setupValidation.salonHoursConfigured, isFalse);
      expect(status.setupValidation.adminHoursConfigured, isFalse);
      expect(status.setupValidation.servicesAssigned, isFalse);
      expect(status.provider!.services.isEmpty, isTrue);
    });

    test('StaffMember model correctly sets isAdminProvider flag', () {
      final regularStaffJson = {
        'id': 'p-1',
        'user_id': 'u-1',
        'salon_id': 's-1',
        'name': 'John Doe',
        'phone': '9876543210',
        'is_active': true,
        'is_admin_provider': false,
        'services': [],
        'working_hours': [],
        'leaves': [],
      };
      final adminStaffJson = {
        'id': 'p-2',
        'user_id': 'u-admin',
        'salon_id': 's-1',
        'name': 'Owner Admin',
        'phone': '9876543211',
        'is_active': true,
        'is_admin_provider': true,
        'services': [],
        'working_hours': [],
        'leaves': [],
      };

      final regularStaff = StaffMember.fromJson(regularStaffJson);
      final adminStaff = StaffMember.fromJson(adminStaffJson);

      expect(regularStaff.isAdminProvider, isFalse);
      expect(adminStaff.isAdminProvider, isTrue);
    });
  });

  group('AdminProviderConfigSheet Widget Tests', () {
    testWidgets('Renders specialization input, schedule switch, and save action', (tester) async {
      final initialStatus = AdminProviderStatus(
        isProviderEnabled: true,
        provider: AdminProviderProfile(
          id: 'prov-1',
          userId: 'u-admin',
          salonId: 'salon-123',
          specialization: 'Director',
          isActive: true,
          autoApproveLeave: true,
          servicesCount: 1,
          services: [
            AdminAssignedService(id: 's1', name: 'Fade Cut', price: 400),
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

      await tester.pumpWidget(
        _wrap(
          AdminProviderConfigSheet(
            salonId: 'salon-123',
            initialStatus: initialStatus,
            initialServices: const [],
            initialSalonHours: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Provider Mode Setup'), findsOneWidget);
      expect(find.text('Specialization / Title'), findsOneWidget);
      expect(find.text('Working Hours & Shifts'), findsOneWidget);
      expect(find.text('Use Salon Working Hours'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('Toggling off salon hours expands 7-day custom schedule configuration', (tester) async {
      final initialStatus = AdminProviderStatus(
        isProviderEnabled: true,
        provider: AdminProviderProfile(
          id: 'prov-1',
          userId: 'u-admin',
          salonId: 'salon-123',
          specialization: 'Director',
          isActive: true,
          autoApproveLeave: true,
          servicesCount: 0,
          services: [],
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

      await tester.pumpWidget(
        _wrap(
          AdminProviderConfigSheet(
            salonId: 'salon-123',
            initialStatus: initialStatus,
            initialServices: const [],
            initialSalonHours: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on the Use Salon Working Hours switch to disable syncing
      await tester.tap(find.text('Use Salon Working Hours'));
      await tester.pumpAndSettle();

      // Should show Custom Schedule header and day names
      expect(find.text('Custom Schedule (7 Days)'), findsOneWidget);
      expect(find.text('Monday'), findsOneWidget);
      expect(find.text('Tuesday'), findsOneWidget);
      expect(find.text('Sunday'), findsOneWidget);
    });
  });
}
