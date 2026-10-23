import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/services/walk_in_api.dart';

void main() {
  group('Multi-Service Extra Selection Unit Tests', () {
    final services = [
      WalkInService(
        id: 'srv-1',
        name: 'Hair Cut',
        category: 'Hair Care',
        price: 300,
        durationMinutes: 30,
      ),
      WalkInService(
        id: 'srv-2',
        name: 'Beard Trim',
        category: 'Beard Care',
        price: 200,
        durationMinutes: 20,
      ),
      WalkInService(
        id: 'srv-3',
        name: 'Face Clean-up',
        category: 'Facial',
        price: 800,
        durationMinutes: 45,
      ),
    ];

    final provider = WalkInProvider(
      id: 'p-1',
      name: 'John Doe',
      serviceIds: ['srv-1', 'srv-2'],
    );

    test('multi-service selection calculates aggregate price and duration correctly', () {
      final selectedServiceIds = <String>{'srv-1', 'srv-2', 'srv-3'};

      final selectedServices =
          services.where((s) => selectedServiceIds.contains(s.id)).toList();

      final totalPrice =
          selectedServices.fold(0.0, (sum, s) => sum + s.price);
      final totalDuration =
          selectedServices.fold(0, (sum, s) => sum + s.durationMinutes);

      expect(selectedServices.length, 3);
      expect(totalPrice, 1300.0);
      expect(totalDuration, 95);
    });

    test('toggling services adds and removes them from selection', () {
      final selectedServiceIds = <String>{};

      // Add service 1
      selectedServiceIds.add('srv-1');
      expect(selectedServiceIds.contains('srv-1'), isTrue);
      expect(selectedServiceIds.length, 1);

      // Add service 2
      selectedServiceIds.add('srv-2');
      expect(selectedServiceIds.length, 2);

      // Toggle off service 1
      selectedServiceIds.remove('srv-1');
      expect(selectedServiceIds.contains('srv-1'), isFalse);
      expect(selectedServiceIds.length, 1);
      expect(selectedServiceIds.contains('srv-2'), isTrue);
    });

    test('untrained warning identifies services not assigned to chosen provider', () {
      final selectedServiceIds = <String>{'srv-1', 'srv-3'};

      final selectedServices =
          services.where((s) => selectedServiceIds.contains(s.id)).toList();

      final untrained = selectedServices
          .where((s) => !provider.serviceIds.contains(s.id))
          .toList();

      expect(untrained.length, 1);
      expect(untrained.first.name, 'Face Clean-up');
    });

    test('clearing all selections resets the selection set', () {
      final selectedServiceIds = <String>{'srv-1', 'srv-2'};
      expect(selectedServiceIds.isNotEmpty, isTrue);

      selectedServiceIds.clear();
      expect(selectedServiceIds.isEmpty, isTrue);
    });
  });
}
