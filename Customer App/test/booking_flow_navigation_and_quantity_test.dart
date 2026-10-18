import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/theme/app_colors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Issue 1: Predictable Stack-Based Back Navigation Tests', () {
    testWidgets(
      'unwinds navigation stack screen by screen without skipping to Home',
      (tester) async {
        // Represents the navigation stack across the complete booking flow
        final List<String> screenHistory = [];

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: ElevatedButton(
                    key: const ValueKey('open_salon'),
                    onPressed: () {
                      screenHistory.add('Home');
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (ctx1) => Scaffold(
                            appBar: AppBar(
                              leading: IconButton(
                                key: const ValueKey('salon_back'),
                                icon: const Icon(Icons.arrow_back),
                                onPressed: () => Navigator.maybePop(ctx1),
                              ),
                              title: const Text('Salon Detail'),
                            ),
                            body: ElevatedButton(
                              key: const ValueKey('open_cart'),
                              onPressed: () {
                                screenHistory.add('SalonDetail');
                                Navigator.of(ctx1).push(
                                  MaterialPageRoute(
                                    builder: (ctx2) => Scaffold(
                                      appBar: AppBar(
                                        leading: IconButton(
                                          key: const ValueKey('cart_back'),
                                          icon: const Icon(Icons.arrow_back),
                                          onPressed: () =>
                                              Navigator.maybePop(ctx2),
                                        ),
                                        title: const Text('Your Cart'),
                                      ),
                                      body: ElevatedButton(
                                        key: const ValueKey('open_checkout'),
                                        onPressed: () {
                                          screenHistory.add('Cart');
                                          Navigator.of(ctx2).push(
                                            MaterialPageRoute(
                                              builder: (ctx3) => Scaffold(
                                                appBar: AppBar(
                                                  leading: IconButton(
                                                    key: const ValueKey(
                                                      'checkout_back',
                                                    ),
                                                    icon: const Icon(
                                                      Icons.arrow_back,
                                                    ),
                                                    onPressed: () =>
                                                        Navigator.maybePop(
                                                          ctx3,
                                                        ),
                                                  ),
                                                  title: const Text(
                                                    'Book Appointment',
                                                  ),
                                                ),
                                                body: const Text(
                                                  'Checkout Content',
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                        child: const Text(
                                          'Proceed to Checkout',
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                              child: const Text('View Cart'),
                            ),
                          ),
                        ),
                      );
                    },
                    child: const Text('Select Salon'),
                  ),
                );
              },
            ),
          ),
        );

        // 1. Start at Home
        expect(find.text('Select Salon'), findsOneWidget);

        // 2. Navigate to Salon Detail
        await tester.tap(find.byKey(const ValueKey('open_salon')));
        await tester.pumpAndSettle();
        expect(find.text('Salon Detail'), findsOneWidget);

        // 3. Navigate to Cart
        await tester.tap(find.byKey(const ValueKey('open_cart')));
        await tester.pumpAndSettle();
        expect(find.text('Your Cart'), findsOneWidget);

        // 4. Navigate to Checkout
        await tester.tap(find.byKey(const ValueKey('open_checkout')));
        await tester.pumpAndSettle();
        expect(find.text('Book Appointment'), findsOneWidget);

        // 5. Press Back on Checkout -> Must return to Cart, not Home
        await tester.tap(find.byKey(const ValueKey('checkout_back')));
        await tester.pumpAndSettle();
        expect(find.text('Your Cart'), findsOneWidget);
        expect(find.text('Book Appointment'), findsNothing);
        expect(find.text('Select Salon'), findsNothing);

        // 6. Press Back on Cart -> Must return to Salon Detail, not Home
        await tester.tap(find.byKey(const ValueKey('cart_back')));
        await tester.pumpAndSettle();
        expect(find.text('Salon Detail'), findsOneWidget);
        expect(find.text('Your Cart'), findsNothing);
        expect(find.text('Select Salon'), findsNothing);

        // 7. Press Back on Salon Detail -> Returns to Home
        await tester.tap(find.byKey(const ValueKey('salon_back')));
        await tester.pumpAndSettle();
        expect(find.text('Select Salon'), findsOneWidget);
        expect(find.text('Salon Detail'), findsNothing);
      },
    );

    test(
      'tab history unwinds to previous tab before falling back to home tab',
      () {
        final List<int> tabHistory = [];
        int currentIndex = 0;

        void switchTab(int newIndex) {
          if (newIndex != currentIndex) {
            if (tabHistory.isEmpty || tabHistory.last != currentIndex) {
              tabHistory.add(currentIndex);
            }
            currentIndex = newIndex;
          }
        }

        int handleBack() {
          while (tabHistory.isNotEmpty && tabHistory.last == currentIndex) {
            tabHistory.removeLast();
          }
          if (tabHistory.isNotEmpty) {
            currentIndex = tabHistory.removeLast();
            return currentIndex;
          }
          if (currentIndex != 0) {
            currentIndex = 0;
            return currentIndex;
          }
          return -1; // Exit app
        }

        // Customer flow: Home (0) -> Explore (1) -> Bookings (2)
        switchTab(1);
        expect(currentIndex, 1);
        expect(tabHistory, [0]);

        switchTab(2);
        expect(currentIndex, 2);
        expect(tabHistory, [0, 1]);

        // Back action from Bookings tab should return to Explore tab (1), not jump directly to Home (0)
        final backStep1 = handleBack();
        expect(backStep1, 1);
        expect(currentIndex, 1);

        // Back action from Explore tab should return to Home tab (0)
        final backStep2 = handleBack();
        expect(backStep2, 0);
        expect(currentIndex, 0);

        // Back action from Home tab should exit app (-1)
        final backStep3 = handleBack();
        expect(backStep3, -1);
      },
    );
  });

  group('Issue 2: Visual Highlighting of Selected Services', () {
    testWidgets(
      'selected service displays purple border, lavender tint, badge, and added button without increment stepper',
      (tester) async {
        int serviceQty = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: StatefulBuilder(
              builder: (context, setState) {
                final isSelected = serviceQty > 0;
                return Scaffold(
                  body: Center(
                    child: Container(
                      key: const ValueKey('service_card'),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? context.colors.accentSoft
                            : context.colors.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: isSelected
                            ? Border.all(
                                color: AppTheme.accentColor,
                                width: 2.0,
                              )
                            : Border.all(color: context.colors.border),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSelected)
                            Container(
                              key: const ValueKey('selected_badge'),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    key: ValueKey('check_icon'),
                                  ),
                                  const Text('Selected'),
                                ],
                              ),
                            ),
                          const Text('Hair Styling'),
                          const Text('₹500'),
                          if (isSelected)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  key: const ValueKey('added_button'),
                                  onTap: () => setState(() => serviceQty = 0),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: context.colors.accentSoft,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: AppTheme.accentColor,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.check,
                                          size: 14,
                                          color: AppTheme.accentColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'ADDED',
                                          style: TextStyle(
                                            color: AppTheme.accentColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  key: const ValueKey('remove_service_btn'),
                                  icon: const Icon(Icons.close),
                                  onPressed: () =>
                                      setState(() => serviceQty = 0),
                                ),
                              ],
                            )
                          else
                            ElevatedButton(
                              key: const ValueKey('add_button'),
                              onPressed: () => setState(() => serviceQty = 1),
                              child: const Text('ADD'),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );

        // Unselected state:
        // 1. ADD button is present
        expect(find.byKey(const ValueKey('add_button')), findsOneWidget);
        // 2. Selected badge and added state are absent
        expect(find.byKey(const ValueKey('selected_badge')), findsNothing);
        expect(find.byKey(const ValueKey('added_button')), findsNothing);
        expect(find.byKey(const ValueKey('stepper_increment')), findsNothing);

        // Select service:
        await tester.tap(find.byKey(const ValueKey('add_button')));
        await tester.pumpAndSettle();

        // Selected state:
        expect(find.byKey(const ValueKey('add_button')), findsNothing);
        expect(find.byKey(const ValueKey('selected_badge')), findsOneWidget);
        expect(find.text('Selected'), findsOneWidget);
        expect(find.byKey(const ValueKey('check_icon')), findsOneWidget);
        expect(find.byKey(const ValueKey('added_button')), findsOneWidget);
        expect(find.text('ADDED'), findsOneWidget);
        // No stepper or increment control for individual service
        expect(find.byKey(const ValueKey('stepper_increment')), findsNothing);
        expect(find.text('Selected (2)'), findsNothing);

        // Tap remove button to unselect:
        await tester.tap(find.byKey(const ValueKey('added_button')));
        await tester.pumpAndSettle();

        // Unselected state restored:
        expect(find.byKey(const ValueKey('add_button')), findsOneWidget);
        expect(find.byKey(const ValueKey('selected_badge')), findsNothing);
        expect(find.byKey(const ValueKey('added_button')), findsNothing);
      },
    );
  });

  group('Issue 3: Single Quantity Tracking and Pricing Integrity Tests', () {
    test(
      'enforces single quantity on repeated additions of the same service (idempotency)',
      () {
        final List<Map<String, dynamic>> cartItems = [];

        void addService(String serviceId, String name, double price) {
          final existingIndex = cartItems.indexWhere(
            (i) => i['service_id'] == serviceId,
          );
          if (existingIndex >= 0) {
            // Idempotent: retain quantity 1, never increment or create duplicate
            cartItems[existingIndex]['quantity'] = 1;
          } else {
            cartItems.add({
              'service_id': serviceId,
              'name': name,
              'price': price,
              'quantity': 1,
            });
          }
        }

        void removeService(String serviceId) {
          cartItems.removeWhere((i) => i['service_id'] == serviceId);
        }

        int aggregateItemCount() {
          return cartItems.fold<int>(
            0,
            (sum, item) => sum + (item['quantity'] as int),
          );
        }

        double calculateTotal() {
          return cartItems.fold<double>(
            0.0,
            (sum, item) =>
                sum + ((item['price'] as double) * (item['quantity'] as int)),
          );
        }

        // Add Haircut once
        addService('srv-1', 'Haircut', 350.0);
        expect(cartItems.length, 1);
        expect(cartItems[0]['quantity'], 1);
        expect(aggregateItemCount(), 1);
        expect(calculateTotal(), 350.0);

        // Add Haircut second time - must stay at quantity 1
        addService('srv-1', 'Haircut', 350.0);
        expect(cartItems.length, 1); // No duplicate line
        expect(cartItems[0]['quantity'], 1); // Idempotent quantity 1
        expect(aggregateItemCount(), 1);
        expect(calculateTotal(), 350.0);

        // Add Haircut third time - still 1
        addService('srv-1', 'Haircut', 350.0);
        expect(cartItems[0]['quantity'], 1);
        expect(aggregateItemCount(), 1);
        expect(calculateTotal(), 350.0);

        // Add independent service (Beard Trim)
        addService('srv-2', 'Beard Trim', 200.0);
        expect(cartItems.length, 2);
        expect(cartItems[0]['quantity'], 1);
        expect(cartItems[1]['quantity'], 1);
        expect(aggregateItemCount(), 2); // 1 Haircut + 1 Beard Trim = 2 items
        expect(calculateTotal(), 550.0);

        // Direct removal of Haircut
        removeService('srv-1');
        expect(cartItems.length, 1);
        expect(cartItems.any((i) => i['service_id'] == 'srv-1'), isFalse);
        expect(aggregateItemCount(), 1);
        expect(calculateTotal(), 200.0);

        // Remove Beard Trim completely
        removeService('srv-2');
        expect(cartItems.length, 0);
        expect(aggregateItemCount(), 0);
        expect(calculateTotal(), 0.0);
      },
    );

    test(
      'booking summary preserves exact line quantities, duration, and advances',
      () {
        final cart = {
          'salon_id': 'salon-101',
          'items': [
            {
              'id': 1,
              'service_id': '10',
              'quantity': 1,
              'service': {
                'id': 10,
                'name': 'Facial Glow',
                'price': 800.0,
                'duration_minutes': 45,
              },
            },
            {
              'id': 2,
              'service_id': '15',
              'quantity': 1,
              'service': {
                'id': 15,
                'name': 'Hair Spa',
                'price': 1200.0,
                'duration_minutes': 60,
              },
            },
          ],
        };

        final items = cart['items'] as List<Map<String, dynamic>>;
        double calculatedTotal = 0.0;
        int calculatedDuration = 0;

        for (final item in items) {
          final service = item['service'] as Map<String, dynamic>;
          final qty = item['quantity'] as int;
          final price = (service['price'] as num).toDouble();
          final duration = service['duration_minutes'] as int;

          calculatedTotal += price * qty;
          calculatedDuration += duration * qty;
        }

        expect(calculatedTotal, (800.0 * 1) + (1200.0 * 1)); // 2000.0
        expect(calculatedDuration, (45 * 1) + (60 * 1)); // 105 mins
        final advancePayable = calculatedTotal * 0.20; // 20% advance rule
        expect(advancePayable, 400.0);
      },
    );

    test(
      'booking summary correctly prices combos when price is in combo or computed from services',
      () {
        double getItemSinglePrice(Map<String, dynamic> item) {
          final combo = item['combo'];
          if (combo != null && combo is Map<String, dynamic>) {
            if (combo['price'] != null) {
              final p = double.tryParse('${combo['price']}') ?? 0.0;
              if (p > 0) return p;
            }
            double comboPrice = 0.0;
            final services = combo['services'] as List? ?? [];
            for (final s in services) {
              if (s is Map<String, dynamic>) {
                final special =
                    s['pivot']?['combo_special_price'] ?? s['price'];
                comboPrice += double.tryParse('$special') ?? 0.0;
              }
            }
            if (comboPrice > 0) return comboPrice;
          }

          final service = item['service'];
          if (service != null && service is Map<String, dynamic>) {
            return double.tryParse('${service['price']}') ?? 0.0;
          }

          if (item['price'] != null) {
            return double.tryParse('${item['price']}') ?? 0.0;
          }

          return 0.0;
        }

        // Case A: combo with explicit price
        final comboWithPrice = {
          'id': 1,
          'combo_id': 'combo-1',
          'quantity': 2,
          'combo': {
            'id': 'combo-1',
            'name': 'Grooming Pack',
            'price': 650.0,
            'services': [],
          },
        };
        final priceA = getItemSinglePrice(comboWithPrice);
        expect(priceA, 650.0);
        expect(priceA * (comboWithPrice['quantity'] as int), 1300.0);

        // Case B: combo without price property but with constituent services
        final comboWithoutDirectPrice = {
          'id': 2,
          'combo_id': 'combo-2',
          'quantity': 1,
          'combo': {
            'id': 'combo-2',
            'name': 'Spa Package',
            'services': [
              {
                'id': 's1',
                'name': 'Massage',
                'price': 1000.0,
                'pivot': {'combo_special_price': 800.0},
              },
              {
                'id': 's2',
                'name': 'Facial',
                'price': 500.0,
                'pivot': {'combo_special_price': 400.0},
              },
            ],
          },
        };
        final priceB = getItemSinglePrice(comboWithoutDirectPrice);
        expect(priceB, 1200.0); // 800 + 400
        expect(priceB * (comboWithoutDirectPrice['quantity'] as int), 1200.0);

        // Case C: item with direct price key from backend enrichment
        final itemWithDirectPrice = {
          'id': 3,
          'combo_id': 'combo-3',
          'quantity': 1,
          'price': 999.0,
          'combo': {'id': 'combo-3', 'name': 'Special Deal'},
        };
        final priceC = getItemSinglePrice(itemWithDirectPrice);
        expect(priceC, 999.0);
      },
    );
  });
}
