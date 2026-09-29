import 'package:http/http.dart' as http;

/// Reads the invoice document for a booking.
///
/// Deliberately does not go through the app's `http_client` wrapper. That
/// wrapper force-logs the customer out on any 401, which is right for an API
/// call carrying a session token and wrong for a signed document link — a
/// document is not a session, and losing the login because a receipt could not
/// be fetched would be a bizarre thing to do to someone mid-booking.
class InvoiceService {
  /// The invoice's HTML, ready to be handed to the print pipeline.
  ///
  /// Throws on anything that is not a usable invoice document, because the
  /// caller needs to tell the customer *something* went wrong rather than hand
  /// a blank page to the PDF engine.
  Future<String> fetchHtml(String signedUrl) async {
    final uri = Uri.tryParse(signedUrl.trim());

    if (uri == null || !uri.hasScheme || !uri.host.isNotEmpty) {
      throw Exception('That invoice link is not valid.');
    }

    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw Exception('That invoice link is not valid.');
    }

    final response = await http.get(uri, headers: {'Accept': 'text/html'});

    if (response.statusCode != 200) {
      throw Exception(
        response.statusCode == 403
            ? 'This invoice link has expired. Open the booking again for a fresh one.'
            : 'Could not load the invoice. Please try again.',
      );
    }

    // A signed URL that has been tampered with comes back as the platform's
    // error page rather than a 403 on some setups. Catching that here stops a
    // login screen being saved to the customer's Downloads folder.
    final body = response.body;
    if (body.trim().isEmpty || (!body.contains('<html') && !body.contains('<!DOCTYPE html'))) {
      throw Exception('That link did not return an invoice.');
    }

    return body;
  }

  /// A filename safe to suggest to the system save dialog.
  ///
  /// Invoice numbers are only ever letters, digits and dashes, but this is not
  /// assumed — a slash in a suggested filename makes some Android pickers
  /// create a directory instead of a file.
  static String fileNameFor(String? invoiceNumber) {
    final cleaned = (invoiceNumber ?? '')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');

    return cleaned.isEmpty ? 'Invoice' : 'Invoice-$cleaned';
  }
}
