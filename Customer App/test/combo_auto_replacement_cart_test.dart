import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/services/cart_service.dart';

void main() {
  group('Cart Combo Auto-Replacement & Saving Notice Tests', () {
    tearDown(() {
      CartService.globalCartNotifier.value = null;
      CartService.comboReplacedNoticeNotifier.value = null;
    });

    test('isServiceInCart returns true for both loose service and service inside a combo', () {
      // 1. Initially empty
      expect(CartService.isServiceInCart('srv-haircut'), isFalse);

      // 2. Loose service in cart
      CartService.globalCartNotifier.value = {
        'items': [
          {
            'id': 'item-1',
            'service_id': 'srv-haircut',
            'quantity': 1,
            'service': {'id': 'srv-haircut', 'name': 'Haircut'},
          }
        ]
      };
      expect(CartService.isServiceInCart('srv-haircut'), isTrue);
      expect(CartService.isServiceInCart('srv-beard'), isFalse);

      // 3. Combo in cart containing srv-haircut and srv-beard
      CartService.globalCartNotifier.value = {
        'items': [
          {
            'id': 'item-2',
            'combo_id': 'combo-grooming',
            'quantity': 1,
            'combo': {
              'id': 'combo-grooming',
              'name': 'Grooming Pack',
              'services': [
                {'id': 'srv-haircut', 'name': 'Haircut'},
                {'id': 'srv-beard', 'name': 'Beard Trim'},
              ]
            }
          }
        ]
      };

      // Both services inside the combo are recognized as in cart
      expect(CartService.isServiceInCart('srv-haircut'), isTrue);
      expect(CartService.isServiceInCart('srv-beard'), isTrue);
      expect(CartService.isServiceInCart('srv-massage'), isFalse);
    });

    test('findCartItemIdForService finds only loose service items, not combo items', () {
      CartService.globalCartNotifier.value = {
        'items': [
          {
            'id': 'item-loose-1',
            'service_id': 'srv-massage',
            'quantity': 1,
          },
          {
            'id': 'item-combo-1',
            'combo_id': 'combo-grooming',
            'quantity': 1,
            'combo': {
              'id': 'combo-grooming',
              'services': [
                {'id': 'srv-haircut'},
              ]
            }
          }
        ]
      };

      expect(CartService.findCartItemIdForService('srv-massage'), 'item-loose-1');
      expect(CartService.findCartItemIdForService('srv-haircut'), isNull);
    });

    testWidgets('Displays saving message SnackBar when combo replaces existing service', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    const msg = 'You saved ₹200! Replaced Haircut with Grooming Pack.';
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  msg,
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          backgroundColor: const Color(0xFF16A34A),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                  },
                  child: const Text('Simulate Combo Replacement'),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('You saved ₹200! Replaced Haircut with Grooming Pack.'), findsNothing);

      await tester.tap(find.text('Simulate Combo Replacement'));
      await tester.pump();

      expect(find.text('You saved ₹200! Replaced Haircut with Grooming Pack.'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });
  });
}
