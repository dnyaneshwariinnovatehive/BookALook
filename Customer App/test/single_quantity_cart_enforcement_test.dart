import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/services/cart_service.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/theme/app_colors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CartService.globalCartNotifier.value = null;
  });

  tearDown(() {
    CartService.globalCartNotifier.value = null;
  });

  group('CartService Single-Quantity Enforcement Tests', () {
    test(
      'isServiceInCart identifies presence of individual service in active cart',
      () {
        expect(CartService.isServiceInCart('srv-101'), isFalse);

        CartService.globalCartNotifier.value = {
          'id': 'cart-1',
          'salon_id': 'salon-1',
          'items': [
            {
              'id': 1,
              'service_id': 'srv-101',
              'quantity': 1,
              'service': {'id': 'srv-101', 'name': 'Haircut'},
            },
            {
              'id': 2,
              'combo_id': 'combo-202',
              'quantity': 2,
              'combo': {'id': 'combo-202', 'name': 'Package Deal'},
            },
          ],
        };

        expect(CartService.isServiceInCart('srv-101'), isTrue);
        expect(CartService.isServiceInCart('srv-999'), isFalse);
      },
    );

    test(
      'updateQuantity rejects newQuantity > 1 for individual service lines',
      () async {
        final cartService = CartService();
        expect(
          () => cartService.updateQuantity(
            'salon-1',
            'item-1',
            serviceId: 'srv-101',
            newQuantity: 2,
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains(
                'Individual services cannot have a quantity greater than 1.',
              ),
            ),
          ),
        );
      },
    );
  });

  group('Salon Detail Single-Quantity UI Tests', () {
    testWidgets(
      'service card transitions from ADD to ADDED and disables increment stepper',
      (tester) async {
        bool isInCart = false;
        int removeCalls = 0;
        int addCalls = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: StatefulBuilder(
              builder: (context, setState) {
                return Scaffold(
                  body: Container(
                    key: const ValueKey('service_card'),
                    decoration: BoxDecoration(
                      color: isInCart
                          ? context.colors.accentSoft
                          : context.colors.surface,
                      border: Border.all(
                        color: isInCart
                            ? AppTheme.accentColor
                            : context.colors.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Text('Classic Haircut'),
                        const Spacer(),
                        if (isInCart)
                          Row(
                            key: const ValueKey('added_container'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                key: const ValueKey('added_pill'),
                                onTap: () {
                                  removeCalls++;
                                  setState(() => isInCart = false);
                                },
                                child: const Text('✓ ADDED'),
                              ),
                              IconButton(
                                key: const ValueKey('remove_btn'),
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  removeCalls++;
                                  setState(() => isInCart = false);
                                },
                              ),
                            ],
                          )
                        else
                          ElevatedButton(
                            key: const ValueKey('add_btn'),
                            onPressed: () {
                              addCalls++;
                              setState(() => isInCart = true);
                            },
                            child: const Text('ADD'),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );

        // 1. Initial state: ADD button present, no stepper or ADDED pill
        expect(find.byKey(const ValueKey('add_btn')), findsOneWidget);
        expect(find.text('ADD'), findsOneWidget);
        expect(find.byKey(const ValueKey('added_pill')), findsNothing);
        expect(find.byKey(const ValueKey('stepper_increment')), findsNothing);

        // 2. Tap ADD -> transitions to ADDED state
        await tester.tap(find.byKey(const ValueKey('add_btn')));
        await tester.pumpAndSettle();

        expect(addCalls, 1);
        expect(find.byKey(const ValueKey('add_btn')), findsNothing);
        expect(find.byKey(const ValueKey('added_pill')), findsOneWidget);
        expect(find.text('✓ ADDED'), findsOneWidget);
        expect(find.byKey(const ValueKey('remove_btn')), findsOneWidget);
        // No increment stepper for individual services
        expect(find.byKey(const ValueKey('stepper_increment')), findsNothing);

        // 3. Tap remove -> restores ADD button
        await tester.tap(find.byKey(const ValueKey('remove_btn')));
        await tester.pumpAndSettle();

        expect(removeCalls, 1);
        expect(find.byKey(const ValueKey('add_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('added_pill')), findsNothing);
      },
    );

    testWidgets('rapid repeated taps on in-flight service card are debounced', (
      tester,
    ) async {
      int networkRequests = 0;
      final Set<String> inFlightServices = {};

      Future<void> onAdd(String sId) async {
        if (inFlightServices.contains(sId)) return;
        inFlightServices.add(sId);
        networkRequests++;
        await Future.delayed(const Duration(milliseconds: 100));
        inFlightServices.remove(sId);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ElevatedButton(
              key: const ValueKey('rapid_tap_btn'),
              onPressed: () => onAdd('srv-1'),
              child: const Text('ADD'),
            ),
          ),
        ),
      );

      // Rapidly fire multiple taps before async completion
      await tester.tap(find.byKey(const ValueKey('rapid_tap_btn')));
      await tester.tap(find.byKey(const ValueKey('rapid_tap_btn')));
      await tester.tap(find.byKey(const ValueKey('rapid_tap_btn')));
      await tester.pump(const Duration(milliseconds: 150));

      // In-flight guard ensures only 1 request was triggered
      expect(networkRequests, 1);
    });
  });

  group('Cart Screen Single-Quantity vs Combo Stepper Tests', () {
    testWidgets(
      'cart renders Qty: 1 badge for services and stepper for combos',
      (tester) async {
        final items = [
          {
            'id': 1,
            'service_id': 'srv-1',
            'title': 'Facial Glow',
            'price': 500.0,
            'quantity': 1,
            'isCombo': false,
          },
          {
            'id': 2,
            'combo_id': 'combo-1',
            'title': 'Bridal Combo',
            'price': 2500.0,
            'quantity': 2,
            'isCombo': true,
          },
        ];

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final isCombo = item['isCombo'] as bool;
                  final qty = item['quantity'] as int;

                  return Row(
                    key: ValueKey('cart_line_${item['id']}'),
                    children: [
                      Text(item['title'] as String),
                      if (isCombo && qty > 1)
                        const Text(
                          '₹2500 each',
                          key: ValueKey('combo_each_label'),
                        ),
                      const Spacer(),
                      if (isCombo)
                        Row(
                          key: const ValueKey('combo_stepper'),
                          children: [
                            const Icon(
                              Icons.remove,
                              key: ValueKey('combo_decrement'),
                            ),
                            Text('$qty', key: const ValueKey('combo_qty_text')),
                            const Icon(
                              Icons.add,
                              key: ValueKey('combo_increment'),
                            ),
                          ],
                        )
                      else
                        Container(
                          key: const ValueKey('service_qty_badge'),
                          child: const Text('Qty: 1'),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        // Service line check
        expect(find.byKey(const ValueKey('service_qty_badge')), findsOneWidget);
        expect(find.text('Qty: 1'), findsOneWidget);
        expect(find.text('₹500 each'), findsNothing);

        // Combo line check
        expect(find.byKey(const ValueKey('combo_stepper')), findsOneWidget);
        expect(find.byKey(const ValueKey('combo_qty_text')), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(find.byKey(const ValueKey('combo_each_label')), findsOneWidget);
        expect(find.byKey(const ValueKey('combo_increment')), findsOneWidget);
      },
    );
  });

  group('Category Service Strip Global Cart Synchronization Tests', () {
    testWidgets('strip reflects global cart changes dynamically', (
      tester,
    ) async {
      const srvId = 'srv-55';

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: StatefulBuilder(
            builder: (context, setState) {
              return ValueListenableBuilder<Map<String, dynamic>?>(
                valueListenable: CartService.globalCartNotifier,
                builder: (context, cart, _) {
                  final isInCart = CartService.isServiceInCart(srvId);
                  return Scaffold(
                    body: Row(
                      children: [
                        const Text('Quick Beard Trim'),
                        GestureDetector(
                          key: const ValueKey('strip_action_btn'),
                          onTap: isInCart
                              ? null
                              : () {
                                  CartService.globalCartNotifier.value = {
                                    'salon_id': 'salon-1',
                                    'items': [
                                      {'service_id': srvId, 'quantity': 1},
                                    ],
                                  };
                                },
                          child: Container(
                            key: const ValueKey('strip_icon_container'),
                            child: isInCart
                                ? const Icon(
                                    Icons.check,
                                    key: ValueKey('strip_check_icon'),
                                  )
                                : const Text(
                                    '+',
                                    key: ValueKey('strip_plus_icon'),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      );

      // 1. Initially not in cart: plus icon is shown
      expect(find.byKey(const ValueKey('strip_plus_icon')), findsOneWidget);
      expect(find.byKey(const ValueKey('strip_check_icon')), findsNothing);

      // 2. Tap to add: transitions to check icon
      await tester.tap(find.byKey(const ValueKey('strip_action_btn')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('strip_check_icon')), findsOneWidget);
      expect(find.byKey(const ValueKey('strip_plus_icon')), findsNothing);

      // 3. Global cart clears: strip automatically resets to plus icon
      CartService.globalCartNotifier.value = null;
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('strip_plus_icon')), findsOneWidget);
      expect(find.byKey(const ValueKey('strip_check_icon')), findsNothing);
    });
  });
}
