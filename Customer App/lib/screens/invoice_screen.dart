import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/invoice_service.dart';
import '../theme/app_theme.dart';

/// Shows a booking's invoice on screen and lets the customer keep a copy.
///
/// The document is reached through a signed link rather than the customer's
/// session, so this works even with no auth header. Keeping a copy is the
/// entire point of an invoice, so the save action goes through the platform
/// print sheet — on Android that is where "Save as PDF" actually lives, and it
/// is the difference between a real file and a screenshot.
class InvoiceScreen extends StatefulWidget {
  final String url;
  final String? invoiceNumber;

  const InvoiceScreen({super.key, required this.url, this.invoiceNumber});

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  final InvoiceService _invoiceService = InvoiceService();

  late final WebViewController _controller;

  /// Kept after the first fetch so a second save does not re-download the
  /// document, and so the saved copy is guaranteed to match what is on screen.
  String? _documentHtml;

  bool _isLoading = true;
  bool _isSaving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _controller = _createController();
  }

  WebViewController _createController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'InvoiceActions',
        onMessageReceived: (_) => _save(),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _error = '';
            });
            _bridgePrintButton();
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            final detail = error.description.trim();
            setState(() {
              _isLoading = false;
              _error = detail.isEmpty ? 'Could not load the invoice.' : detail;
            });
          },
        ),
      );

    final uri = Uri.tryParse(widget.url.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      // Safe to set directly: this runs before the first build.
      _isLoading = false;
      _error = 'That invoice link is not valid.';
    } else {
      controller.loadRequest(uri);
    }

    return controller;
  }

  /// The invoice page has its own "Print / Save as PDF" button, but
  /// `window.print()` is a no-op inside an Android WebView. Point it at the
  /// same handler the toolbar uses so the button on the page is not a decoy.
  Future<void> _bridgePrintButton() async {
    try {
      await _controller.runJavaScript('''
        (function () {
          if (window.__invoiceBridged) return;
          window.__invoiceBridged = true;
          window.print = function () { window.InvoiceActions.postMessage('print'); };
        })();
      ''');
    } catch (_) {
      // Losing the bridge only costs the page's own button. The toolbar action
      // is the primary path and does not depend on any of this.
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      // A missing or expired link fails here, and a browser would fail the same
      // way, so this one is reported plainly rather than given a dead fallback.
      try {
        _documentHtml ??= await _invoiceService.fetchHtml(widget.url);
      } catch (e) {
        if (mounted) _showMessage(e.toString().replaceFirst('Exception: ', ''));
        return;
      }
      if (!mounted) return;

      // The printing package deprecates HTML rasterisation in favour of
      // building PDFs natively, which would mean a second copy of the invoice
      // layout in Dart that drifts from the SuperAdmin-customisable one.
      // Rendering the real document is worth the deprecated call.
      //
      // Pinned to A4 whatever the customer picks as a save destination, with
      // margins coming from the invoice's own @page rule. Letting the printer
      // dictate the size is how an invoice ends up half empty on one page and
      // clipped on the next.
      await Printing.layoutPdf(
        // ignore: deprecated_member_use
        onLayout: (format) => Printing.convertHtml(
          html: _documentHtml!,
          format: format,
          baseUrl: Uri.tryParse(widget.url.trim())?.origin,
        ),
        name: InvoiceService.fileNameFor(widget.invoiceNumber),
        format: PdfPageFormat.a4,
        usePrinterSettings: false,
      );
    } catch (_) {
      // Rasterising HTML depends on a partly deprecated corner of the printing
      // package. An invoice a customer cannot keep is worse than one they keep
      // the long way round, so hand off to the browser, where the same
      // document is one tap from a real Save as PDF.
      if (mounted) _showBrowserFallback();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showBrowserFallback() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Could not build the PDF here.'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(label: 'Open in browser', onPressed: _openExternally),
        ),
      );
  }

  Future<void> _openExternally() async {
    final uri = Uri.tryParse(widget.url.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _reload() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    _documentHtml = null;

    try {
      await _controller.loadRequest(Uri.parse(widget.url.trim()));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final number = (widget.invoiceNumber ?? '').trim();

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Invoice',
                style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold)),
            if (number.isNotEmpty)
              Text(number,
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    color: isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight,
                  )),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Save as PDF',
            onPressed: (_isSaving || _error.isNotEmpty) ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _error.isNotEmpty ? _buildError(isDark) : _buildDocument(),
    );
  }

  Widget _buildDocument() {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          Center(
            child: CircularProgressIndicator(color: AppTheme.accentColor),
          ),
      ],
    );
  }

  Widget _buildError(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_rounded,
                size: 44,
                color: isDark ? AppTheme.darkTextLight : Colors.grey.shade400),
            const SizedBox(height: 14),
            Text(
              _error,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 14,
                height: 1.4,
                color: isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded, size: 19),
              label: const Text('Try again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? AppTheme.darkButtonBg : AppTheme.accentColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
