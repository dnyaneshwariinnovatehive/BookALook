import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/services/invoice_service.dart';
import 'package:customer_app/widgets/invoice_actions.dart';

Map<String, dynamic> bookingWith(Object? invoice) => {
      'id': 7,
      'invoice': invoice,
    };

Widget harness(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('InvoiceInfo.fromBooking', () {
    test('reads the number and url off a real payload', () {
      final info = InvoiceInfo.fromBooking(bookingWith({
        'number': 'BAL-2026-00042',
        'issued_at': '2026-09-28T09:00:00+05:30',
        'url': 'https://api.bookalook.in/api/invoices/9?signature=abc',
      }));

      expect(info, isNotNull);
      expect(info!.number, 'BAL-2026-00042');
      expect(info.url, 'https://api.bookalook.in/api/invoices/9?signature=abc');
    });

    test('is null when the booking has no invoice yet', () {
      expect(InvoiceInfo.fromBooking(bookingWith(null)), isNull);
    });

    test('is null when the invoice is not a map', () {
      expect(InvoiceInfo.fromBooking(bookingWith('BAL-2026-00042')), isNull);
    });

    test('is null when the url is missing or blank', () {
      expect(InvoiceInfo.fromBooking(bookingWith({'number': 'BAL-1'})), isNull);
      expect(InvoiceInfo.fromBooking(bookingWith({'url': '   '})), isNull);
    });

    test('is null for a url that is not http(s)', () {
      expect(
        InvoiceInfo.fromBooking(bookingWith({'url': 'javascript:alert(1)'})),
        isNull,
      );
      expect(
        InvoiceInfo.fromBooking(bookingWith({'url': 'file:///etc/passwd'})),
        isNull,
      );
    });

    test('is null for a relative url', () {
      expect(
        InvoiceInfo.fromBooking(bookingWith({'url': '/api/invoices/9'})),
        isNull,
      );
    });

    test('survives a missing number and still gives back the link', () {
      final info =
          InvoiceInfo.fromBooking(bookingWith({'url': 'https://x.test/i/9'}));

      expect(info, isNotNull);
      expect(info!.number, isEmpty);
    });
  });

  group('InvoiceService.fileNameFor', () {
    test('keeps an ordinary invoice number intact', () {
      expect(InvoiceService.fileNameFor('BAL-2026-00042'), 'Invoice-BAL-2026-00042');
    });

    test('strips characters that some Android pickers treat as directories', () {
      expect(InvoiceService.fileNameFor('a/b'), 'Invoice-a-b');
    });

    test('falls back rather than offering a nameless file', () {
      expect(InvoiceService.fileNameFor(null), 'Invoice');
      expect(InvoiceService.fileNameFor('   '), 'Invoice');
    });
  });

  group('invoice actions', () {
    const withInvoice = {
      'id': 7,
      'invoice': {
        'number': 'BAL-2026-00042',
        'url': 'https://api.bookalook.in/api/invoices/9?signature=abc',
      },
    };

    testWidgets('the card link shows the invoice number', (tester) async {
      await tester.pumpWidget(harness(InvoiceLinkButton(booking: withInvoice)));

      expect(find.text('View invoice'), findsOneWidget);
      expect(find.text('BAL-2026-00042'), findsOneWidget);
    });

    testWidgets('the card link is absent for a booking with no invoice', (tester) async {
      await tester.pumpWidget(harness(InvoiceLinkButton(booking: bookingWith(null))));

      expect(find.text('View invoice'), findsNothing);
    });

    testWidgets('the details button names the invoice', (tester) async {
      await tester.pumpWidget(harness(InvoiceActionButton(booking: withInvoice)));

      expect(find.text('View invoice BAL-2026-00042'), findsOneWidget);
    });

    testWidgets('the details button falls back to plain wording', (tester) async {
      await tester.pumpWidget(harness(InvoiceActionButton(booking: bookingWith({
        'url': 'https://api.bookalook.in/api/invoices/9?signature=abc',
      }))));

      expect(find.text('View invoice'), findsOneWidget);
    });
  });
}
