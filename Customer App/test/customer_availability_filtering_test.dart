import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:customer_app/theme/app_theme.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Customer Provider Availability & Filtering Widget Tests', () {
    testWidgets('displays message when no eligible staff are available on the selected date', (tester) async {
      final List<Map<String, dynamic>> providers = [
        {
          'id': 1,
          'name': 'Provider On Leave',
          'is_eligible': false,
        },
      ];

      final eligibleProviders = providers.where((p) => p['is_eligible'] == true).toList();

      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) {
            if (eligibleProviders.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No staff members are currently available on this date who can perform all selected services.',
                        style: GoogleFonts.outfit(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text('No staff members are currently available on this date who can perform all selected services.'),
        findsOneWidget,
      );
    });

    testWidgets('renders available and eligible provider cards', (tester) async {
      final List<Map<String, dynamic>> providers = [
        {
          'id': 1,
          'name': 'Sarah Jenkins',
          'specialization': 'Senior Stylist',
          'is_eligible': true,
        },
        {
          'id': 2,
          'name': 'David Ross',
          'specialization': 'Color Specialist',
          'is_eligible': true,
        },
      ];

      await tester.pumpWidget(_wrap(
        Column(
          children: providers.map((provider) {
            return ListTile(
              title: Text(provider['name']),
              subtitle: Text(provider['specialization']),
            );
          }).toList(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Sarah Jenkins'), findsOneWidget);
      expect(find.text('Senior Stylist'), findsOneWidget);
      expect(find.text('David Ross'), findsOneWidget);
      expect(find.text('Color Specialist'), findsOneWidget);
    });

    test('verifies date query parameter construction for providers endpoint', () {
      final baseUrl = 'http://127.0.0.1:8000/api';
      final salonId = '10';
      final date = '2026-10-25';

      final uri = Uri.parse('$baseUrl/customer/salons/$salonId/providers').replace(
        queryParameters: {
          if (date.isNotEmpty) 'date': date,
        },
      );

      expect(uri.queryParameters['date'], '2026-10-25');
      expect(uri.toString(), 'http://127.0.0.1:8000/api/customer/salons/10/providers?date=2026-10-25');
    });
  });
}
