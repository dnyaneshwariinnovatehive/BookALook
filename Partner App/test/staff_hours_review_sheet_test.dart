import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/models/salon_working_hour.dart';
import 'package:partner_app/models/staff_models.dart';
import 'package:partner_app/widgets/staff_hours_review_sheet.dart';

void main() {
  // Salon now opens 10:00–18:00, closed Sundays.
  final salonHours = List.generate(
    7,
    (d) => SalonWorkingHour(
      dayOfWeek: d,
      isClosed: d == 0,
      openTime: d == 0 ? null : '10:00:00',
      closeTime: d == 0 ? null : '18:00:00',
    ),
  );

  List<StaffWorkingHour> shift(String start, String end) => List.generate(
        7,
        (d) => StaffWorkingHour(dayOfWeek: d, isWeeklyOff: d == 0, shiftStart: d == 0 ? null : start, shiftEnd: d == 0 ? null : end),
      );

  StaffMember member(String id, String name, {required bool follows, List<StaffWorkingHour>? hours}) => StaffMember(
        id: id,
        userId: 'u-$id',
        salonId: 'salon-1',
        baseSalary: 0,
        commissionPercentage: 10,
        isActive: true,
        useSalonHours: follows,
        user: {'name': name},
        workingHours: hours ?? shift('10:00:00', '18:00:00'),
      );

  Future<List<Map<String, dynamic>>> pumpSheet(WidgetTester tester, List<StaffMember> staff, {List<int?>? result}) async {
    final calls = <Map<String, dynamic>>[];
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final r = await showStaffHoursReviewSheet(
                  context,
                  salonId: 'salon-1',
                  staff: staff,
                  salonHours: salonHours,
                  save: ({required salonId, required staffId, required followSalon, hours}) async {
                    calls.add({'staffId': staffId, 'followSalon': followSalon, 'hours': hours});
                  },
                );
                result?.add(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return calls;
  }

  testWidgets('lists every provider and flags a shift outside the new hours', (tester) async {
    await pumpSheet(tester, [
      member('a', 'Asha', follows: true),
      member('b', 'Bilal', follows: false, hours: shift('09:00:00', '20:00:00')),
    ]);

    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Bilal'), findsOneWidget);
    expect(find.textContaining('Outside the new salon hours'), findsOneWidget);
  });

  testWidgets('moving a custom-shift provider onto salon hours saves only them', (tester) async {
    final calls = await pumpSheet(tester, [
      member('a', 'Asha', follows: true),
      member('b', 'Bilal', follows: false, hours: shift('09:00:00', '20:00:00')),
    ]);

    await tester.tap(find.byKey(const ValueKey('staff_hours_follow_b')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('staff_hours_save')));
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(calls.single['staffId'], 'b');
    expect(calls.single['followSalon'], isTrue);
    expect(calls.single['hours'], isNull);
  });

  testWidgets('taking a provider off salon hours saves their own shift', (tester) async {
    final calls = await pumpSheet(tester, [member('a', 'Asha', follows: true)]);

    await tester.tap(find.byKey(const ValueKey('staff_hours_follow_a')));
    await tester.pumpAndSettle();
    expect(find.text('Hide custom hours'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('staff_hours_save')));
    await tester.pumpAndSettle();

    expect(calls.single['followSalon'], isFalse);
    expect((calls.single['hours'] as List<StaffWorkingHour>), hasLength(7));
  });

  testWidgets('skip changes nobody', (tester) async {
    final results = <int?>[];
    final calls = await pumpSheet(tester, [member('a', 'Asha', follows: true)], result: results);

    await tester.tap(find.byKey(const ValueKey('staff_hours_skip')));
    await tester.pumpAndSettle();

    expect(calls, isEmpty);
    expect(results.single, isNull);
  });
}
