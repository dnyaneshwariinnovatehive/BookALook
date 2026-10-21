import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/models/staff_models.dart';

void main() {
  group('StaffMember Working Hours Model Tests', () {
    test('parses use_salon_hours: true correctly', () {
      final json = {
        'id': 1,
        'user_id': 10,
        'salon_id': 5,
        'name': 'John Doe',
        'role': 'stylist',
        'is_active': true,
        'use_salon_hours': true,
        'services': [],
        'working_hours': [
          {
            'day_of_week': 1,
            'is_working': true,
            'start_time': '09:00:00',
            'end_time': '18:00:00',
            'break_start_time': '13:00:00',
            'break_end_time': '14:00:00',
          }
        ],
      };
      final staff = StaffMember.fromJson(json);
      expect(staff.id, '1');
      expect(staff.userId, '10');
      expect(staff.salonId, '5');
      expect(staff.useSalonHours, isTrue);
      expect(staff.workingHours.length, 1);
      expect(staff.workingHours.first.isWeeklyOff, isFalse);
      expect(staff.workingHours.first.shiftStart, '09:00:00');
      expect(staff.workingHours.first.shiftEnd, '18:00:00');
      expect(staff.workingHours.first.breakStart, '13:00:00');
      expect(staff.workingHours.first.breakEnd, '14:00:00');
    });

    test('parses use_salon_hours: false correctly', () {
      final json = {
        'id': 'provider-2',
        'user_id': 'user-11',
        'salon_id': 'salon-5',
        'name': 'Jane Smith',
        'role': 'stylist',
        'is_active': true,
        'use_salon_hours': false,
        'services': [],
        'working_hours': [
          {
            'day_of_week': 2,
            'is_working': false,
          }
        ],
      };
      final staff = StaffMember.fromJson(json);
      expect(staff.id, 'provider-2');
      expect(staff.useSalonHours, isFalse);
      expect(staff.workingHours.length, 1);
      expect(staff.workingHours.first.isWeeklyOff, isTrue);
    });

    test('defaults use_salon_hours to true when omitted', () {
      final json = {
        'id': 3,
        'user_id': 12,
        'salon_id': 5,
        'name': 'Alex Ray',
        'role': 'stylist',
        'is_active': true,
        'services': [],
        'working_hours': [],
      };
      final staff = StaffMember.fromJson(json);
      expect(staff.useSalonHours, isTrue);
    });

    test('sorts working_hours by day_of_week in ascending order', () {
      final json = {
        'id': 4,
        'user_id': 14,
        'salon_id': 5,
        'name': 'Taylor Swift',
        'role': 'stylist',
        'is_active': true,
        'working_hours': [
          {'day_of_week': 5, 'is_working': true},
          {'day_of_week': 1, 'is_working': true},
          {'day_of_week': 0, 'is_working': false},
          {'day_of_week': 3, 'is_working': true},
        ],
      };
      final staff = StaffMember.fromJson(json);
      expect(staff.workingHours.map((h) => h.dayOfWeek).toList(), [0, 1, 3, 5]);
    });
  });

  group('StaffWorkingHour Model Tests', () {
    test('parses all shift and break timing fields properly with start_time keys', () {
      final hour = StaffWorkingHour.fromJson({
        'day_of_week': 3,
        'is_working': true,
        'start_time': '10:00:00',
        'end_time': '19:00:00',
        'break_start_time': '14:00:00',
        'break_end_time': '15:00:00',
      });

      expect(hour.dayOfWeek, 3);
      expect(hour.isWeeklyOff, isFalse);
      expect(hour.shiftStart, '10:00:00');
      expect(hour.shiftEnd, '19:00:00');
      expect(hour.breakStart, '14:00:00');
      expect(hour.breakEnd, '15:00:00');
    });

    test('parses all shift and break timing fields properly with shift_start keys', () {
      final hour = StaffWorkingHour.fromJson({
        'day_of_week': 4,
        'is_weekly_off': true,
        'shift_start': '09:00',
        'shift_end': '18:00',
        'break_start': '13:00',
        'break_end': '14:00',
      });

      expect(hour.dayOfWeek, 4);
      expect(hour.isWeeklyOff, isTrue);
      expect(hour.shiftStart, '09:00:00');
      expect(hour.shiftEnd, '18:00:00');
      expect(hour.breakStart, '13:00:00');
      expect(hour.breakEnd, '14:00:00');
    });
  });
}
