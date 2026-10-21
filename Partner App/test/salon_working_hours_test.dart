import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/models/salon_working_hour.dart';

void main() {
  group('SalonWorkingHour Model Tests', () {
    test('parses open day JSON correctly', () {
      final json = {
        'day_of_week': 1,
        'is_closed': false,
        'open_time': '10:00:00',
        'close_time': '20:00:00',
      };

      final hour = SalonWorkingHour.fromJson(json);
      expect(hour.dayOfWeek, 1);
      expect(hour.isClosed, false);
      expect(hour.openTime, '10:00:00');
      expect(hour.closeTime, '20:00:00');
    });

    test('parses closed day JSON with null times correctly', () {
      final json = {
        'day_of_week': 0,
        'is_closed': true,
        'open_time': null,
        'close_time': null,
      };

      final hour = SalonWorkingHour.fromJson(json);
      expect(hour.dayOfWeek, 0);
      expect(hour.isClosed, true);
      expect(hour.openTime, isNull);
      expect(hour.closeTime, isNull);
    });

    test('toJson outputs exact expected contract structure', () {
      final hour = SalonWorkingHour(
        dayOfWeek: 2,
        isClosed: false,
        openTime: '09:00:00',
        closeTime: '18:00:00',
      );

      final map = hour.toJson();
      expect(map['day_of_week'], 2);
      expect(map['is_closed'], false);
      expect(map['open_time'], '09:00:00');
      expect(map['close_time'], '18:00:00');
    });

    test('handles numeric 1 / 0 for is_closed from backend', () {
      final closedHour = SalonWorkingHour.fromJson({
        'day_of_week': 3,
        'is_closed': 1,
        'open_time': null,
        'close_time': null,
      });
      expect(closedHour.isClosed, true);

      final openHour = SalonWorkingHour.fromJson({
        'day_of_week': 4,
        'is_closed': 0,
        'open_time': '09:00:00',
        'close_time': '17:00:00',
      });
      expect(openHour.isClosed, false);
    });
  });

  group('Error Message Extraction Tests', () {
    test('extracts clean validation error message from nested errors', () {
      const responseBody = '{"message":"The given data was invalid.","errors":{"working_hours.1.close_time":["Closing time must be after opening time."]}}';
      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      String errorMessage = responseBody;

      if (decoded['errors'] is Map) {
        final errors = decoded['errors'] as Map;
        final firstErrorList = errors.values.first;
        if (firstErrorList is List && firstErrorList.isNotEmpty) {
          errorMessage = firstErrorList.first.toString();
        }
      }

      expect(errorMessage, 'Closing time must be after opening time.');
    });

    test('extracts message when errors field is absent', () {
      const responseBody = '{"message":"Failed to update working hours: Database connection timed out."}';
      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      final errorMessage = decoded['message']?.toString() ?? responseBody;

      expect(errorMessage, 'Failed to update working hours: Database connection timed out.');
    });
  });
}
