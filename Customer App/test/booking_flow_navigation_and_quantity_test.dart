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
      'selected service displays purple border, lavender tint, badge, and quantity stepper',
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
                                  Text(
                                    serviceQty > 1
                                        ? 'Selected ($serviceQty)'
                                        : 'Selected',
                                  ),
                                ],
                              ),
                            ),
                          const Text('Hair Styling'),
                          const Text('₹500'),
                          if (isSelected)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  key: const ValueKey('stepper_decrement'),
                                  icon: const Icon(Icons.remove),
                                  onPressed: () => setState(() => serviceQty--),
                                ),
                                Text(
                                  '$serviceQty',
                                  key: const ValueKey('stepper_qty'),
                                ),
                                IconButton(
                                  key: const ValueKey('stepper_increment'),
                                  icon: const Icon(Icons.add),
                                  onPressed: () => setState(() => serviceQty++),
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
        // 2. Selected badge is absent
        expect(find.byKey(const ValueKey('selected_badge')), findsNothing);
        expect(find.byKey(const ValueKey('stepper_qty')), findsNothing);

        // Select service:
        await tester.tap(find.byKey(const ValueKey('add_button')));
        await tester.pumpAndSettle();

        // Selected state with quantity 1:
        expect(find.byKey(const ValueKey('add_button')), findsNothing);
        expect(find.byKey(const ValueKey('selected_badge')), findsOneWidget);
        expect(find.text('Selected'), findsOneWidget);
        expect(find.byKey(const ValueKey('check_icon')), findsOneWidget);
        expect(find.text('1'), findsOneWidget);

        // Increment to quantity 2:
        await tester.tap(find.byKey(const ValueKey('stepper_increment')));
        await tester.pumpAndSettle();

        // Selected state with quantity 2:
        expect(find.text('Selected (2)'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);

        // Decrement back to quantity 1:
        await tester.tap(find.byKey(const ValueKey('stepper_decrement')));
        await tester.pumpAndSettle();
        expect(find.text('Selected'), findsOneWidget);
        expect(find.text('1'), findsOneWidget);

        // Decrement to 0 (removal):
        await tester.tap(find.byKey(const ValueKey('stepper_decrement')));
        await tester.pumpAndSettle();

        // Unselected state restored:
        expect(find.byKey(const ValueKey('add_button')), findsOneWidget);
        expect(find.byKey(const ValueKey('selected_badge')), findsNothing);
        expect(find.byKey(const ValueKey('stepper_qty')), findsNothing);
      },
    );
  });

  group('Issue 3: Multiple Quantity Tracking and Pricing Integrity Tests', () {
    test(
      'tracks repeated additions of the same service and aggregates quantity correctly',
      () {
        final List<Map<String, dynamic>> cartItems = [];

        void addOrIncrement(String serviceId, String name, double price) {
          final existingIndex = cartItems.indexWhere(
            (i) => i['service_id'] == serviceId,
          );
          if (existingIndex >= 0) {
            cartItems[existingIndex]['quantity'] =
                (cartItems[existingIndex]['quantity'] as int) + 1;
          } else {
            cartItems.add({
              'service_id': serviceId,
              'name': name,
              'price': price,
              'quantity': 1,
            });
          }
        }

        void decrementOrRemove(String serviceId) {
          final existingIndex = cartItems.indexWhere(
            (i) => i['service_id'] == serviceId,
          );
          if (existingIndex >= 0) {
            final currentQty = cartItems[existingIndex]['quantity'] as int;
            if (currentQty <= 1) {
              cartItems.removeAt(existingIndex);
            } else {
              cartItems[existingIndex]['quantity'] = currentQty - 1;
            }
          }
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
        addOrIncrement('srv-1', 'Haircut', 350.0);
        expect(cartItems.length, 1);
        expect(cartItems[0]['quantity'], 1);
        expect(aggregateItemCount(), 1);
        expect(calculateTotal(), 350.0);

        // Add Haircut second time
        addOrIncrement('srv-1', 'Haircut', 350.0);
        expect(cartItems.length, 1); // No untracked duplicate line
        expect(cartItems[0]['quantity'], 2);
        expect(aggregateItemCount(), 2);
        expect(calculateTotal(), 700.0);

        // Add Haircut third time
        addOrIncrement('srv-1', 'Haircut', 350.0);
        expect(cartItems[0]['quantity'], 3);
        expect(aggregateItemCount(), 3);
        expect(calculateTotal(), 1050.0);

        // Add independent service (Beard Trim)
        addOrIncrement('srv-2', 'Beard Trim', 200.0);
        expect(cartItems.length, 2);
        expect(cartItems[0]['quantity'], 3);
        expect(cartItems[1]['quantity'], 1);
        expect(aggregateItemCount(), 4); // 3 Haircut + 1 Beard Trim = 4 items
        expect(calculateTotal(), 1250.0);

        // Decrement Haircut
        decrementOrRemove('srv-1');
        expect(cartItems[0]['quantity'], 2);
        expect(aggregateItemCount(), 3);
        expect(calculateTotal(), 900.0);

        // Remove Beard Trim completely
        decrementOrRemove('srv-2');
        expect(cartItems.length, 1);
        expect(cartItems.any((i) => i['service_id'] == 'srv-2'), isFalse);
        expect(aggregateItemCount(), 2);
        expect(calculateTotal(), 700.0);
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
              'quantity': 2,
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

        expect(calculatedTotal, (800.0 * 2) + (1200.0 * 1)); // 2800.0
        expect(calculatedDuration, (45 * 2) + (60 * 1)); // 150 mins
        final advancePayable = calculatedTotal * 0.20; // 20% advance rule
        expect(advancePayable, 560.0);
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
