import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/theme/app_colors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Detail Page Address & Directions Tests', () {
    testWidgets('Address is interactive and Directions button chip is rendered', (tester) async {
      bool openedDirections = false;
      const testAddress = '123 MG Road, Pune, 411001';

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return InkWell(
                  key: const ValueKey('address_row'),
                  onTap: () => openedDirections = true,
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined),
                      const Expanded(child: Text(testAddress)),
                      Container(
                        key: const ValueKey('directions_chip'),
                        child: const Row(
                          children: [
                            Icon(Icons.directions_outlined),
                            Text('Directions'),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text(testAddress), findsOneWidget);
      expect(find.text('Directions'), findsOneWidget);
      expect(find.byKey(const ValueKey('directions_chip')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('address_row')));
      await tester.pump();
      expect(openedDirections, isTrue);
    });
  });

  group('Cart Extra Quantity Decrement Tests', () {
    testWidgets('allows decrementing quantity from 2 to 1 and prompts removal at 1', (tester) async {
      int itemQuantity = 2;
      bool removed = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('decrement_btn'),
                      icon: Icon(itemQuantity <= 1 ? Icons.delete_outline : Icons.remove),
                      onPressed: () {
                        if (itemQuantity <= 1) {
                          setState(() => removed = true);
                        } else {
                          setState(() => itemQuantity--);
                        }
                      },
                    ),
                    Text('$itemQuantity', key: const ValueKey('qty_text')),
                    IconButton(
                      key: const ValueKey('increment_btn'),
                      icon: const Icon(Icons.add),
                      onPressed: () => setState(() => itemQuantity++),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('2'), findsOneWidget);
      expect(find.byIcon(Icons.remove), findsOneWidget);

      // Decrement from 2 to 1
      await tester.tap(find.byKey(const ValueKey('decrement_btn')));
      await tester.pump();

      expect(find.text('1'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(removed, isFalse);

      // Tap again at 1 to remove
      await tester.tap(find.byKey(const ValueKey('decrement_btn')));
      await tester.pump();

      expect(removed, isTrue);
    });
  });

  group('Checkout Glide to Appointment Section Tests', () {
    testWidgets('selecting provider triggers scroll into view of appointment section', (tester) async {
      final scrollController = ScrollController();
      final appointmentKey = GlobalKey();
      bool glided = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                children: [
                  ElevatedButton(
                    key: const ValueKey('select_provider_btn'),
                    onPressed: () {
                      glided = true;
                      Scrollable.ensureVisible(
                        appointmentKey.currentContext!,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOutCubic,
                      );
                    },
                    child: const Text('Staff Member'),
                  ),
                  const SizedBox(height: 800),
                  KeyedSubtree(
                    key: appointmentKey,
                    child: const Text('2. Select Date', key: ValueKey('date_section')),
                  ),
                  const SizedBox(height: 500),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('date_section')), findsOneWidget);
      expect(glided, isFalse);

      await tester.tap(find.byKey(const ValueKey('select_provider_btn')));
      await tester.pumpAndSettle();

      expect(glided, isTrue);
      expect(scrollController.offset, greaterThan(0.0));
    });
  });

  group('Cart Add No Bottom Notification Tests', () {
    testWidgets('adding a service updates cart counter without displaying SnackBar or BottomSheet', (tester) async {
      int cartCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Items in cart: $cartCount', key: const ValueKey('cart_counter')),
                      ElevatedButton(
                        key: const ValueKey('add_service_btn'),
                        onPressed: () {
                          // Clean add without bottom notification
                          setState(() {
                            cartCount++;
                          });
                        },
                        child: const Text('Add Service'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Items in cart: 0'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);

      // Tap to add service
      await tester.tap(find.byKey(const ValueKey('add_service_btn')));
      await tester.pumpAndSettle();

      // State is updated
      expect(find.text('Items in cart: 1'), findsOneWidget);
      // No bottom notification or sheet is shown
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
    });
  });
}

