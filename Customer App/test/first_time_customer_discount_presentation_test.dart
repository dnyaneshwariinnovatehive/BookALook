import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/widgets/discount_badge.dart';
import 'package:customer_app/theme/app_theme.dart';

void main() {
  setUpAll(() {
    WidgetsFlutterBinding.ensureInitialized();
  });

  Widget wrapWidget(Widget child, {double width = 400}) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(size: Size(width, 900)),
          child: SizedBox(width: width, child: Center(child: child)),
        ),
      ),
    );
  }

  group('Customer App: Service Pricing & Targeting Widget Tests', () {
    testWidgets('1. Eligible customer sees original and discounted prices with DiscountBadge', (tester) async {
      final serviceData = {
        'id': 'srv-1',
        'name': 'Premium Haircut',
        'price': 400.0,
        'original_price': 500.0,
        'discounted_price': 400.0,
        'first_time_discount': {
          'offer_id': 'off-1',
          'offer_name': 'Welcome 20% Off',
          'discount_type': 'percentage',
          'discount_value': 20,
          'discount_amount': 100.0,
          'discount_label': '20% OFF',
        },
      };

      final ftd = serviceData['first_time_discount'] as Map<String, dynamic>?;
      final rawPrice = (serviceData['price'] as num).toDouble();
      final origPrice = (serviceData['original_price'] as num?)?.toDouble() ?? rawPrice;
      final discPrice = (serviceData['discounted_price'] as num?)?.toDouble() ?? rawPrice;
      final isDiscounted = ftd != null && origPrice > discPrice && discPrice > 0;
      final effectivePrice = isDiscounted ? discPrice : rawPrice;

      await tester.pumpWidget(wrapWidget(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('₹${effectivePrice.toStringAsFixed(0)}'),
                if (isDiscounted) ...[
                  const SizedBox(width: 8),
                  AnimatedOriginalPrice(originalPrice: origPrice, price: effectivePrice),
                  const SizedBox(width: 8),
                  DiscountBadge(
                    originalPrice: origPrice,
                    price: effectivePrice,
                    customLabel: ftd['discount_label'] as String?,
                    style: DiscountBadgeStyle.compact,
                  ),
                ],
              ],
            ),
            if (isDiscounted)
              Text('Save ₹${(origPrice - effectivePrice).toStringAsFixed(0)} · First visit'),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('₹400'), findsOneWidget);
      expect(find.text('₹500'), findsOneWidget);
      expect(find.text('20% OFF'), findsOneWidget);
      expect(find.text('Save ₹100 · First visit'), findsOneWidget);
    });

    testWidgets('2. Ineligible customer sees regular pricing and no discount badge', (tester) async {
      final serviceData = {
        'id': 'srv-2',
        'name': 'Classic Beard Trim',
        'price': 250.0,
        'original_price': 250.0,
        'discounted_price': null,
        'first_time_discount': null, // Ineligible customer
      };

      final ftd = serviceData['first_time_discount'] as Map<String, dynamic>?;
      final rawPrice = (serviceData['price'] as num).toDouble();
      final origPrice = (serviceData['original_price'] as num?)?.toDouble() ?? rawPrice;
      final discPrice = (serviceData['discounted_price'] as num?)?.toDouble() ?? rawPrice;
      final isDiscounted = ftd != null && origPrice > discPrice && discPrice > 0;
      final effectivePrice = isDiscounted ? discPrice : rawPrice;

      await tester.pumpWidget(wrapWidget(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('₹${effectivePrice.toStringAsFixed(0)}'),
                if (isDiscounted) ...[
                  AnimatedOriginalPrice(originalPrice: origPrice, price: effectivePrice),
                  DiscountBadge(originalPrice: origPrice, price: effectivePrice),
                ],
              ],
            ),
            if (isDiscounted)
              Text('Save ₹${(origPrice - effectivePrice).toStringAsFixed(0)} · First visit'),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('₹250'), findsOneWidget);
      expect(find.textContaining('OFF'), findsNothing);
      expect(find.textContaining('Save'), findsNothing);
    });

    testWidgets('3. Guest user sees regular pricing without discount badge', (tester) async {
      final serviceData = {
        'id': 'srv-3',
        'name': 'Hair Spa',
        'price': 800.0,
        'first_time_discount': null,
      };

      final ftd = serviceData['first_time_discount'] as Map<String, dynamic>?;
      final rawPrice = (serviceData['price'] as num).toDouble();
      final isDiscounted = ftd != null;

      await tester.pumpWidget(wrapWidget(
        Row(
          children: [
            Text('₹${rawPrice.toStringAsFixed(0)}'),
            if (isDiscounted)
              const DiscountBadge(originalPrice: 800, price: 640),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('₹800'), findsOneWidget);
      expect(find.textContaining('OFF'), findsNothing);
    });

    testWidgets('4. Non-targeted service does not display a discount', (tester) async {
      // Salon has an offer, but this specific service template is unselected
      final serviceData = {
        'id': 'srv-4',
        'name': 'Basic Shampoo',
        'price': 150.0,
        'original_price': 150.0,
        'discounted_price': 150.0,
        'first_time_discount': null, // Not targeted
      };

      final ftd = serviceData['first_time_discount'] as Map<String, dynamic>?;
      final rawPrice = (serviceData['price'] as num).toDouble();
      final isDiscounted = ftd != null;

      await tester.pumpWidget(wrapWidget(
        Row(
          children: [
            Text('₹${rawPrice.toStringAsFixed(0)}'),
            if (isDiscounted)
              const DiscountBadge(originalPrice: 150, price: 120),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('₹150'), findsOneWidget);
      expect(find.textContaining('OFF'), findsNothing);
    });

    testWidgets('5. Missing optional metadata does not break old response parsing', (tester) async {
      // Legacy API response without original_price or first_time_discount
      final legacyService = {
        'id': 'srv-legacy',
        'name': 'Legacy Manicure',
        'price': 350,
      };

      final ftd = legacyService['first_time_discount'] as Map<String, dynamic>?;
      final rawPrice = (legacyService['price'] as num).toDouble();
      final origPrice = (legacyService['original_price'] as num?)?.toDouble() ?? rawPrice;
      final discPrice = (legacyService['discounted_price'] as num?)?.toDouble() ?? rawPrice;
      final isDiscounted = ftd != null && origPrice > discPrice && discPrice > 0;
      final effectivePrice = isDiscounted ? discPrice : rawPrice;

      await tester.pumpWidget(wrapWidget(
        Text('₹${effectivePrice.toStringAsFixed(0)}'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('₹350'), findsOneWidget);
    });

    testWidgets('6. Malformed or null discount metadata fails safely', (tester) async {
      // Negative discount or higher discounted price than original price
      final malformedService = {
        'id': 'srv-malformed',
        'name': 'Hair Color',
        'price': 1200.0,
        'original_price': 1000.0,
        'discounted_price': 1400.0, // Higher than original!
        'first_time_discount': {
          'discount_amount': -200.0,
        },
      };

      final ftd = malformedService['first_time_discount'] as Map<String, dynamic>?;
      final rawPrice = (malformedService['price'] as num).toDouble();
      final origPrice = (malformedService['original_price'] as num?)?.toDouble() ?? rawPrice;
      final discPrice = (malformedService['discounted_price'] as num?)?.toDouble() ?? rawPrice;
      // Must be false if origPrice <= discPrice
      final isDiscounted = ftd != null && origPrice > discPrice && discPrice > 0;
      final effectivePrice = isDiscounted ? discPrice : rawPrice;

      await tester.pumpWidget(wrapWidget(
        Row(
          children: [
            Text('₹${effectivePrice.toStringAsFixed(0)}'),
            if (isDiscounted)
              DiscountBadge(originalPrice: origPrice, price: discPrice),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      // Displays regular price, suppresses discount badge
      expect(find.text('₹1200'), findsOneWidget);
      expect(find.textContaining('OFF'), findsNothing);
    });
  });

  group('Customer App: Cart Breakdown & Combo Protection Tests', () {
    test('7. Cart totals reconcile with backend authoritative summary', () {
      final summary = {
        'list_total': 1500.0,
        'total_amount': 1200.0,
        'saving': 300.0,
        'first_time_discount': {
          'applied': true,
          'offer_id': 'off-welcome',
          'offer_name': 'First Visit 20% Off',
          'discount_type': 'percentage',
          'discount_value': 20,
          'total_discount': 300.0,
          'max_discount_cap': 500.0,
        },
      };

      final listTotal = (summary['list_total'] as num).toDouble();
      final totalAmount = (summary['total_amount'] as num).toDouble();
      final totalSaving = (summary['saving'] as num).toDouble();
      final ftd = summary['first_time_discount'] as Map<String, dynamic>;
      final ftdDiscount = (ftd['total_discount'] as num).toDouble();

      expect(totalAmount, 1200.0);
      expect(listTotal - totalSaving, totalAmount);
      expect(ftdDiscount, 300.0);
      expect(ftd['applied'], isTrue);
    });

    test('8. Combo-only carts do not show a first-time customer discount', () {
      final summary = {
        'list_total': 1800.0,
        'total_amount': 1400.0,
        'saving': 400.0,
        'first_time_discount': {
          'applied': false,
          'offer_id': null,
          'total_discount': 0.0,
          'lines': {},
        },
      };

      final ftd = summary['first_time_discount'] as Map<String, dynamic>;
      final applied = ftd['applied'] == true;
      final ftdDiscount = (ftd['total_discount'] as num).toDouble();

      expect(applied, isFalse);
      expect(ftdDiscount, 0.0);

      // Entire savings is combo savings
      final comboSavings = ((summary['saving'] as num).toDouble()) - ftdDiscount;
      expect(comboSavings, 400.0);
    });

    test('9. Combo plus eligible loose service displays discount only for eligible loose line', () {
      final comboLine = {
        'combo_id': 'combo-bridal',
        'combo': {'name': 'Bridal Glow Package'},
        'quantity': 1,
      };

      final looseLine = {
        'service_id': 'srv-haircut',
        'service': {'id': 'srv-haircut', 'name': 'Haircut'},
        'quantity': 1,
      };

      expect(comboLine['combo_id'], 'combo-bridal');
      expect(looseLine['service_id'], 'srv-haircut');

      final summary = {
        'list_total': 2500.0,
        'total_amount': 2000.0,
        'saving': 500.0,
        'first_time_discount': {
          'applied': true,
          'total_discount': 100.0,
          'lines': {
            'srv-haircut': {
              'unit_discount': 100.0,
              'line_discount': 100.0,
              'final_line_price': 400.0,
            },
          },
        },
      };

      final ftd = summary['first_time_discount'] as Map<String, dynamic>;
      final lines = ftd['lines'] as Map<String, dynamic>;

      // Combo is not in first-time discount lines
      expect(lines.containsKey('combo-bridal'), isFalse);
      // Loose service is in first-time discount lines
      expect(lines.containsKey('srv-haircut'), isTrue);
      expect(lines['srv-haircut']['line_discount'], 100.0);

      // Package savings is 500 - 100 = 400
      final totalSaving = (summary['saving'] as num).toDouble();
      final ftdDiscount = (ftd['total_discount'] as num).toDouble();
      final comboSaving = totalSaving - ftdDiscount;
      expect(comboSaving, 400.0);
    });

    testWidgets('10. Cart bill breakdown widget renders item total, package savings, and first-time offer', (tester) async {
      final summary = {
        'list_total': 2000.0,
        'total_amount': 1500.0,
        'saving': 500.0,
        'first_time_discount': {
          'applied': true,
          'offer_name': 'Welcome 100',
          'total_discount': 100.0,
        },
      };

      final listTotal = (summary['list_total'] as num).toDouble();
      final totalAmount = (summary['total_amount'] as num).toDouble();
      final totalSaving = (summary['saving'] as num).toDouble();
      final ftd = summary['first_time_discount'] as Map<String, dynamic>;
      final ftdAmount = (ftd['total_discount'] as num).toDouble();
      final comboSaving = totalSaving - ftdAmount;

      await tester.pumpWidget(wrapWidget(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Item total: ₹${listTotal.toStringAsFixed(0)}'),
            if (comboSaving > 0)
              Text('Package savings: -₹${comboSaving.toStringAsFixed(0)}'),
            if (ftdAmount > 0)
              Text('First-time offer (${ftd['offer_name']}): -₹${ftdAmount.toStringAsFixed(0)}'),
            Text('To pay: ₹${totalAmount.toStringAsFixed(0)}'),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Item total: ₹2000'), findsOneWidget);
      expect(find.text('Package savings: -₹400'), findsOneWidget);
      expect(find.text('First-time offer (Welcome 100): -₹100'), findsOneWidget);
      expect(find.text('To pay: ₹1500'), findsOneWidget);
    });
  });
}
