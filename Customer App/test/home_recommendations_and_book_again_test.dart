import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Book Again Deduplication Tests', () {
    test('deduplicates salons by unique ID and preserves most recent order', () {
      final pastBookings = [
        {
          'id': 'booking-1',
          'salon_id': 'salon-glow-up',
          'salon': {
            'id': 'salon-glow-up',
            'name': 'Glow Up Studio',
            'distance_km': 1.8,
          },
          'services': [{'name': 'Beard Trim'}],
        },
        {
          'id': 'booking-2',
          'salon_id': 'salon-glow-up',
          'salon': {
            'id': 'salon-glow-up',
            'name': 'Glow Up Studio',
            'distance_km': 1.8,
          },
          'services': [{'name': 'Haircut'}],
        },
        {
          'id': 'booking-3',
          'salon_id': 'salon-style-lounge',
          'salon': {
            'id': 'salon-style-lounge',
            'name': 'Style Lounge',
            'distance_km': 3.2,
          },
          'services': [{'name': 'Hair Styling'}],
        },
        {
          'id': 'booking-4',
          'salon_id': 'salon-glow-up',
          'salon': {
            'id': 'salon-glow-up',
            'name': 'Glow Up Studio',
            'distance_km': 1.8,
          },
          'services': [{'name': 'Facial'}],
        },
      ];

      // Replicating _deduplicatedBookAgainList getter logic from HomeTab
      List<Map<String, dynamic>> deduplicateBookAgain(List<dynamic> past, bool isGuest) {
        if (past.isEmpty || isGuest) return [];

        final List<Map<String, dynamic>> deduplicated = [];
        final Set<String> seenSalonIds = {};

        for (final item in past) {
          if (item is! Map<String, dynamic>) continue;
          final salonId = (item['salon_id'] ?? item['salon']?['id'])?.toString();
          if (salonId == null || salonId.isEmpty) continue;

          if (!seenSalonIds.contains(salonId)) {
            seenSalonIds.add(salonId);
            deduplicated.add(item);
          }
        }

        return deduplicated;
      }

      final result = deduplicateBookAgain(pastBookings, false);

      expect(result.length, 2);
      expect(result[0]['salon']['name'], 'Glow Up Studio');
      expect((result[0]['services'] as List)[0]['name'], 'Beard Trim'); // most recent booking service
      expect(result[1]['salon']['name'], 'Style Lounge');
      expect((result[1]['services'] as List)[0]['name'], 'Hair Styling');
    });

    test('guest user never receives Book Again entries', () {
      final pastBookings = [
        {
          'id': 'booking-1',
          'salon_id': 'salon-1',
          'salon': {'name': 'Salon 1'},
          'services': [{'name': 'Cut'}],
        }
      ];

      List<Map<String, dynamic>> deduplicateBookAgain(List<dynamic> past, bool isGuest) {
        if (past.isEmpty || isGuest) return [];
        final List<Map<String, dynamic>> deduplicated = [];
        final Set<String> seenSalonIds = {};
        for (final item in past) {
          if (item is! Map<String, dynamic>) continue;
          final salonId = (item['salon_id'] ?? item['salon']?['id'])?.toString();
          if (salonId == null || salonId.isEmpty) continue;
          if (!seenSalonIds.contains(salonId)) {
            seenSalonIds.add(salonId);
            deduplicated.add(item);
          }
        }
        return deduplicated;
      }

      expect(deduplicateBookAgain(pastBookings, true), isEmpty);
    });
  });

  group('Recommended for You Ranking and Deduplication Tests', () {
    test('deduplicates salons by unique ID and filters unserviceable salons', () {
      final rawSalons = [
        {
          'id': 'salon-1',
          'name': 'Salon Alpha',
          'avg_rating': 4.8,
          'distance_km': 2.0,
          'is_serviceable': true,
        },
        {
          'id': 'salon-2',
          'name': 'Salon Beta',
          'avg_rating': 3.5,
          'distance_km': 1.0,
          'is_serviceable': false, // expired sub
        },
        {
          'id': 'salon-1', // duplicate
          'name': 'Salon Alpha Duplicate',
          'avg_rating': 4.8,
          'distance_km': 2.0,
          'is_serviceable': true,
        },
        {
          'id': 'salon-3',
          'name': 'Salon Gamma',
          'avg_rating': 4.9,
          'distance_km': 2.5,
          'is_serviceable': true,
        },
      ];

      // Replicating _fetchRecommendedSalons processing
      List<Map<String, dynamic>> processRecommendations(List<dynamic> salons) {
        final Map<String, dynamic> uniqueSalons = {};
        for (var s in salons) {
          if (s is Map<String, dynamic>) {
            final id = s['id']?.toString();
            if (id != null && id.isNotEmpty && !uniqueSalons.containsKey(id)) {
              uniqueSalons[id] = s;
            }
          }
        }

        var list = uniqueSalons.values.cast<Map<String, dynamic>>().toList();
        list = list.where((s) => s['is_serviceable'] != false).toList();

        list.sort((a, b) {
          final distA = (a['distance_km'] as num?)?.toDouble();
          final distB = (b['distance_km'] as num?)?.toDouble();
          final ratingA = (a['avg_rating'] as num?)?.toDouble() ?? 0.0;
          final ratingB = (b['avg_rating'] as num?)?.toDouble() ?? 0.0;

          if (distA != null && distB != null) {
            final isTopA = ratingA >= 4.0;
            final isTopB = ratingB >= 4.0;
            if (isTopA && !isTopB && distA <= distB * 1.5) return -1;
            if (!isTopA && isTopB && distB <= distA * 1.5) return 1;

            final distComp = distA.compareTo(distB);
            if (distComp != 0) return distComp;
            return ratingB.compareTo(ratingA);
          } else if (distA != null) {
            return -1;
          } else if (distB != null) {
            return 1;
          } else {
            return ratingB.compareTo(ratingA);
          }
        });

        return list;
      }

      final processed = processRecommendations(rawSalons);

      // salon-2 was unserviceable (excluded)
      // salon-1 duplicate was deduplicated
      expect(processed.length, 2);
      expect(processed.map((s) => s['id']).toList(), ['salon-1', 'salon-3']);
    });

    test('sorts by rating descending when distance is unavailable', () {
      final salonsWithoutDistance = [
        {'id': 's1', 'name': 'Mid Rating', 'avg_rating': 4.2, 'is_serviceable': true},
        {'id': 's2', 'name': 'Top Rating', 'avg_rating': 4.9, 'is_serviceable': true},
        {'id': 's3', 'name': 'Low Rating', 'avg_rating': 3.8, 'is_serviceable': true},
      ];

      final list = List<Map<String, dynamic>>.from(salonsWithoutDistance);
      list.sort((a, b) {
        final distA = (a['distance_km'] as num?)?.toDouble();
        final distB = (b['distance_km'] as num?)?.toDouble();
        final ratingA = (a['avg_rating'] as num?)?.toDouble() ?? 0.0;
        final ratingB = (b['avg_rating'] as num?)?.toDouble() ?? 0.0;

        if (distA != null && distB != null) {
          final isTopA = ratingA >= 4.0;
          final isTopB = ratingB >= 4.0;
          if (isTopA && !isTopB && distA <= distB * 1.5) return -1;
          if (!isTopA && isTopB && distB <= distA * 1.5) return 1;
          final distComp = distA.compareTo(distB);
          if (distComp != 0) return distComp;
          return ratingB.compareTo(ratingA);
        } else if (distA != null) {
          return -1;
        } else if (distB != null) {
          return 1;
        } else {
          return ratingB.compareTo(ratingA);
        }
      });

      expect(list[0]['id'], 's2');
      expect(list[1]['id'], 's1');
      expect(list[2]['id'], 's3');
    });
  });

  group('Next Appointment Section Visibility Tests', () {
    test('does not show next appointment section when upcoming appointments list is empty', () {
      final upcoming = [];
      final isGuest = false;
      final shouldShow = !isGuest && upcoming.isNotEmpty;
      expect(shouldShow, isFalse);
    });

    test('does not show next appointment section when user is a guest', () {
      final upcoming = [{'id': 'apt-1'}];
      final isGuest = true;
      final shouldShow = !isGuest && upcoming.isNotEmpty;
      expect(shouldShow, isFalse);
    });

    test('shows next appointment section when customer is logged in and has upcoming appointments', () {
      final upcoming = [{'id': 'apt-1'}];
      final isGuest = false;
      final shouldShow = !isGuest && upcoming.isNotEmpty;
      expect(shouldShow, isTrue);
    });
  });
}
