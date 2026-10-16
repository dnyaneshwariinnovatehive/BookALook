import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/screens/dashboard/tabs/more/more_menu_catalog.dart';
import 'package:partner_app/screens/dashboard/tabs/more/more_search_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Create mock context items for pure testing
  final mockItems = [
    const MoreMenuItem(
      id: 'salon_offers',
      title: 'Offers & Discounts',
      category: 'Salon management',
      subtitle: 'Promo codes, first-time customer & percentage discounts',
      icon: Icons.local_offer,
      iconColor: Colors.purple,
      keywords: [
        'offers',
        'discounts',
        'offers & discounts',
        'promotions',
        'deals',
        'coupons',
        'promo code',
        'first time offer',
        'festival discount',
        'sale',
        'percentage off',
        'flat discount',
      ],
    ),
    const MoreMenuItem(
      id: 'salon_timings',
      title: 'Change Salon Timings',
      category: 'Salon management',
      subtitle: 'Working hours, opening & closing shifts, weekly off',
      icon: Icons.access_time,
      iconColor: Colors.amber,
      keywords: [
        'timings',
        'change salon timings',
        'working hours',
        'opening hours',
        'closing hours',
        'schedule',
        'open',
        'close',
        'days',
        'holiday',
        'shifts',
        'slots',
        'time',
      ],
    ),
    const MoreMenuItem(
      id: 'staff_payroll',
      title: 'Staff Payroll',
      category: 'Payments & payroll',
      subtitle: 'Base salaries, commissions, leave deductions & payslips',
      icon: Icons.groups,
      iconColor: Colors.indigo,
      keywords: [
        'staff payroll',
        'payroll',
        'salary',
        'staff salary',
        'payslip',
        'wages',
        'commissions',
        'staff pay',
        'team compensation',
        'deductions',
        'attendance deduction',
        'monthly pay',
        'staff',
      ],
    ),
    const MoreMenuItem(
      id: 'my_wallet',
      title: 'My Wallet',
      category: 'Payments & payroll',
      subtitle: 'Reward coins, points balance & plan redemptions',
      icon: Icons.account_balance_wallet,
      iconColor: Colors.orange,
      keywords: [
        'wallet',
        'my wallet',
        'coins',
        'reward coins',
        'rewards',
        'cashback',
        'balance',
        'redeem',
        'points',
        'money',
        'funds',
      ],
    ),
    const MoreMenuItem(
      id: 'salon_payouts',
      title: 'Payouts from BookALook',
      category: 'Payments & payroll',
      subtitle: 'Weekly bank transfers, settlement UTR & commissions',
      icon: Icons.account_balance,
      iconColor: Colors.blueGrey,
      keywords: [
        'payouts',
        'payouts from bookalook',
        'settlement',
        'bank transfer',
        'bank account',
        'direct deposit',
        'commission deducted',
        'weekly payout',
        'money',
        'finance',
        'earnings withdrawal',
      ],
    ),
    const MoreMenuItem(
      id: 'automated_messaging',
      title: 'Automated Messaging',
      category: 'Insights & communication',
      subtitle: 'WhatsApp 25-day reminders & birthday greetings',
      icon: Icons.mark_chat_read,
      iconColor: Colors.green,
      keywords: [
        'automated messaging',
        'whatsapp',
        'messaging',
        'reminder',
        'birthday reminder',
        '25 day reminder',
        'auto message',
        'retention',
        'chat',
        'sms',
      ],
    ),
    const MoreMenuItem(
      id: 'salon_qr',
      title: 'Your QR Code',
      category: 'Salon management',
      subtitle: 'Download & print salon booking QR standee poster',
      icon: Icons.qr_code_2,
      iconColor: Colors.purple,
      keywords: [
        'qr code',
        'your qr code',
        'qr',
        'barcode',
        'standee',
        'poster',
        'scan',
        'print qr',
        'share qr',
      ],
    ),
    const MoreMenuItem(
      id: 'upgrade_plan',
      title: 'Upgrade / Renew Plan',
      category: 'Payments & payroll',
      subtitle: 'Starter & Growth tiers, plan features & payment proof upload',
      icon: Icons.upgrade,
      iconColor: Colors.deepPurple,
      keywords: [
        'upgrade plan',
        'renew subscription',
        'buy plan',
        'change plan',
        'pricing table',
        'plans',
        'pricing',
      ],
    ),
    const MoreMenuItem(
      id: 'legal_privacy',
      title: 'Privacy Policy',
      category: 'Account & app settings',
      subtitle: 'BookALook data privacy, confidentiality & security terms',
      icon: Icons.lock,
      iconColor: Colors.blue,
      keywords: ['privacy policy', 'privacy', 'data privacy', 'security'],
    ),
    const MoreMenuItem(
      id: 'dark_mode',
      title: 'Dark Mode',
      category: 'Account & app settings',
      subtitle: 'Toggle dark or light visual appearance',
      icon: Icons.dark_mode,
      iconColor: Colors.amber,
      type: MenuItemType.inlineToggle,
      keywords: [
        'dark mode',
        'light mode',
        'theme',
        'night mode',
        'appearance',
      ],
    ),
    const MoreMenuItem(
      id: 'push_notifications',
      title: 'Push Notifications',
      category: 'Account & app settings',
      subtitle: 'Device push alerts for appointments & reminders',
      icon: Icons.notifications,
      iconColor: Colors.orange,
      type: MenuItemType.inlineToggle,
      keywords: [
        'push notifications',
        'push alert',
        'fcm',
        'notification sound',
      ],
    ),
  ];

  group('MoreSearchEngine — Matching and Relevance Ranking', () {
    test('1. Exact title matching returns highest score', () {
      final results = MoreSearchEngine.search(
        query: 'Your QR Code',
        items: mockItems,
      );

      expect(results, isNotEmpty);
      expect(results.first.item.id, equals('salon_qr'));
      expect(results.first.score, equals(1000));
    });

    test('2. Case-insensitive and trimmed queries match correctly', () {
      final results = MoreSearchEngine.search(
        query: '   oFfErS & DiScOuNtS   ',
        items: mockItems,
      );

      expect(results, isNotEmpty);
      expect(results.first.item.id, equals('salon_offers'));
    });

    test('3. Partial phrases find the expected item', () {
      final results = MoreSearchEngine.search(
        query: 'timings',
        items: mockItems,
      );

      expect(results, isNotEmpty);
      expect(results.first.item.id, equals('salon_timings'));
    });

    test('4. Synonym and natural user query tests (Required Examples)', () {
      // "offers" -> Offers & Discounts
      var res = MoreSearchEngine.search(query: 'offers', items: mockItems);
      expect(res.first.item.id, equals('salon_offers'));

      // "discount" -> Offers & Discounts
      res = MoreSearchEngine.search(query: 'discount', items: mockItems);
      expect(res.first.item.id, equals('salon_offers'));

      // "first time offer" -> Offers & Discounts
      res = MoreSearchEngine.search(
        query: 'first time offer',
        items: mockItems,
      );
      expect(res.first.item.id, equals('salon_offers'));

      // "working hours" -> Change Salon Timings
      res = MoreSearchEngine.search(query: 'working hours', items: mockItems);
      expect(res.first.item.id, equals('salon_timings'));

      // "opening hours" -> Change Salon Timings
      res = MoreSearchEngine.search(query: 'opening hours', items: mockItems);
      expect(res.first.item.id, equals('salon_timings'));

      // "salary" -> Staff Payroll
      res = MoreSearchEngine.search(query: 'salary', items: mockItems);
      expect(res.first.item.id, equals('staff_payroll'));

      // "payslip" -> Staff Payroll
      res = MoreSearchEngine.search(query: 'payslip', items: mockItems);
      expect(res.first.item.id, equals('staff_payroll'));

      // "staff pay" -> Staff Payroll
      res = MoreSearchEngine.search(query: 'staff pay', items: mockItems);
      expect(res.first.item.id, equals('staff_payroll'));

      // "whatsapp" -> Automated Messaging
      res = MoreSearchEngine.search(query: 'whatsapp', items: mockItems);
      expect(res.first.item.id, equals('automated_messaging'));

      // "dark mode" -> Dark Mode
      res = MoreSearchEngine.search(query: 'dark mode', items: mockItems);
      expect(res.first.item.id, equals('dark_mode'));

      // "push notifications" -> Push Notifications
      res = MoreSearchEngine.search(
        query: 'push notifications',
        items: mockItems,
      );
      expect(res.first.item.id, equals('push_notifications'));

      // "upgrade plan" -> Upgrade / Renew Plan
      res = MoreSearchEngine.search(query: 'upgrade plan', items: mockItems);
      expect(res.first.item.id, equals('upgrade_plan'));

      // "privacy policy" -> Privacy Policy
      res = MoreSearchEngine.search(query: 'privacy policy', items: mockItems);
      expect(res.first.item.id, equals('legal_privacy'));
    });

    test('5. "money" returns both Wallet and Payouts ranked appropriately', () {
      final results = MoreSearchEngine.search(query: 'money', items: mockItems);

      final ids = results.map((r) => r.item.id).toList();
      expect(ids, contains('my_wallet'));
      expect(ids, contains('salon_payouts'));
    });

    test(
      '6. Typo tolerance finds terms with 1 edit distance for words >= 4 chars',
      () {
        // "offrs" -> offers
        final offerResults = MoreSearchEngine.search(
          query: 'offrs',
          items: mockItems,
        );
        expect(offerResults, isNotEmpty);
        expect(offerResults.first.item.id, equals('salon_offers'));

        // "timngs" -> timings
        final timingResults = MoreSearchEngine.search(
          query: 'timngs',
          items: mockItems,
        );
        expect(timingResults, isNotEmpty);
        expect(timingResults.first.item.id, equals('salon_timings'));
      },
    );

    test('7. Empty and whitespace-only queries return empty list', () {
      expect(MoreSearchEngine.search(query: '', items: mockItems), isEmpty);
      expect(MoreSearchEngine.search(query: '   ', items: mockItems), isEmpty);
    });

    test('8. Nonsense queries return empty list without false positives', () {
      final results = MoreSearchEngine.search(
        query: 'xyz123nonsense',
        items: mockItems,
      );
      expect(results, isEmpty);
    });
  });
}
