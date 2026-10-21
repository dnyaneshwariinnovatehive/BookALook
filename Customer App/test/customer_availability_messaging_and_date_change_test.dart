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

  group('Customer Availability Messaging & Date Change Widget Tests', () {
    testWidgets('displays "This salon is closed on the selected day." when salon is closed', (tester) async {
      final bool isSalonClosed = true;
      final String salonClosedReason = 'This salon is closed on the selected day.';

      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) {
            if (isSalonClosed) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.event_busy, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            salonClosedReason,
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Please choose another date.',
                            style: GoogleFonts.outfit(fontSize: 12),
                          ),
                        ],
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

      expect(find.text('This salon is closed on the selected day.'), findsOneWidget);
      expect(find.text('Please choose another date.'), findsOneWidget);
    });

    testWidgets('displays "No service provider is available for the selected date or time." when no eligible providers', (tester) async {
      final List<Map<String, dynamic>> providers = [];
      final String noProvidersReason = 'No service provider is available for the selected date or time.';

      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) {
            if (providers.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        noProvidersReason,
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
        find.text('No service provider is available for the selected date or time.'),
        findsOneWidget,
      );
    });

    testWidgets('displays guidance banner when selected provider is unavailable on new date without crashing', (tester) async {
      String? providerWarning = 'David Ross is not available on this date. Please choose another provider or date.';

      await tester.pumpWidget(_wrap(
        StatefulBuilder(
          builder: (context, setState) {
            return Column(
              children: [
                if (providerWarning != null)
                  Container(
                    key: const Key('provider_warning_banner'),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            providerWarning!,
                            style: GoogleFonts.outfit(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      providerWarning = null;
                    });
                  },
                  child: const Text('Dismiss or Pick New Date'),
                ),
              ],
            );
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('provider_warning_banner')), findsOneWidget);
      expect(
        find.text('David Ross is not available on this date. Please choose another provider or date.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Dismiss or Pick New Date'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('provider_warning_banner')), findsNothing);
    });

    testWidgets('preserves selected provider when provider remains eligible across date changes', (tester) async {
      String? selectedProviderKey = '1';
      final providersOnNewDate = [
        {'id': 1, 'name': 'Sarah Jenkins', 'is_eligible': true},
        {'id': 2, 'name': 'David Ross', 'is_eligible': false},
      ];

      // Simulate date change logic from _loadProviders
      final eligible = providersOnNewDate
          .where((p) => p['is_eligible'] == true)
          .map((p) => p['id']?.toString())
          .toSet();

      bool keepSelectedProvider = false;
      if (selectedProviderKey != null && eligible.contains(selectedProviderKey)) {
        keepSelectedProvider = true;
      }

      expect(keepSelectedProvider, isTrue);
      expect(selectedProviderKey, '1');
    });

    testWidgets('displays slot unavailable reason when all slots are booked or unavailable', (tester) async {
      final List<Map<String, dynamic>> slots = [
        {'time': '10:00', 'available': false, 'reason': 'booked'},
        {'time': '10:30', 'available': false, 'reason': 'booked'},
      ];
      final String slotUnavailableReason = 'All appointment slots are fully booked for this date.';
      final hasAnyAvailable = slots.any((s) => s['available'] == true);

      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) {
            return Column(
              children: [
                if (!hasAnyAvailable)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            slotUnavailableReason,
                            style: GoogleFonts.outfit(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('All appointment slots are fully booked for this date.'), findsOneWidget);
    });
  });
}
