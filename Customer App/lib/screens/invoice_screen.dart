import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/invoice_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';
import '../utils/error_text.dart';
import '../utils/bottom_clearance.dart';
import '../widgets/feedback_states.dart';

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
  bool _showLoader = true;
  bool _isSaving = false;
  String _error = '';

  /// Why saving the PDF did not work, shown above the document until
  /// dismissed. [_saveFallback] offers the browser when the device could not
  /// build the PDF itself.
  String? _saveProblem;
  bool _saveFallback = false;

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
    setState(() {
      _isSaving = true;
      _saveProblem = null;
    });

    try {
      // A missing or expired link fails here, and a browser would fail the same
      // way, so this one is reported plainly rather than given a dead fallback.
      try {
        _documentHtml ??= await _invoiceService.fetchHtml(widget.url);
      } catch (e) {
        if (mounted) {
          setState(() {
            _saveProblem = describeError(e, fallback: 'Could not download the invoice. Please try again.');
            _saveFallback = false;
          });
        }
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

  /// Used to be an 8-second SnackBar carrying the only way out ("Open in
  /// browser"); miss it and the customer had no route to the PDF at all.
  /// Now it stays above the document until they act on it or dismiss it.
  void _showBrowserFallback() {
    setState(() {
      _saveProblem = 'Could not build the PDF on this device. You can save it from your browser instead.';
      _saveFallback = true;
    });
  }

  Future<void> _openExternally() async {
    final uri = Uri.tryParse(widget.url.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _reload() async {
    setState(() {
      _isLoading = true;
      _showLoader = true;
      _error = '';
    });
    _documentHtml = null;

    try {
      await _controller.loadRequest(Uri.parse(widget.url.trim()));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = describeError(e, fallback: 'Could not load the invoice.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final number = (widget.invoiceNumber ?? '').trim();

    return Scaffold(
      backgroundColor: context.colors.documentBg,
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
                    color: context.colors.textTertiary,
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
      body: _error.isNotEmpty
          ? _buildError()
          : Column(
              children: [
                if (_saveProblem != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: InlineStatus(
                      message: _saveProblem!,
                      kind: _saveFallback ? StatusKind.warning : StatusKind.error,
                      onRetry: _saveFallback ? _openExternally : _save,
                      retryLabel: _saveFallback ? 'Open in browser' : 'Try again',
                      onDismiss: () => setState(() => _saveProblem = null),
                    ),
                  ),
                Expanded(child: _buildDocument()),
              ],
            ),
    );
  }

  Widget _buildDocument() {
    return Stack(
      children: [
        // The PDF fills the page, but the last of it has to stay readable: the
        // system navigation bar sits on top of whatever the WebView paints.
        Padding(
          padding: EdgeInsets.only(bottom: bottomClearance(context)),
          child: WebViewWidget(controller: _controller),
        ),
        
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_showLoader,
            child: AnimatedOpacity(
              opacity: _showLoader ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              child: _InvoiceAnimatedLoader(
                isWebViewReady: !_isLoading,
                onFinished: () {
                  if (mounted) {
                    setState(() {
                      _showLoader = false;
                    });
                  }
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return ErrorState(
      icon: Icons.receipt_long_rounded,
      title: 'Could not open this invoice',
      message: _error,
      onRetry: _reload,
    );
  }
}

enum _LoaderPhase { preparing, shimmer, finalizing }

class _InvoiceAnimatedLoader extends StatefulWidget {
  final bool isWebViewReady;
  final VoidCallback onFinished;

  const _InvoiceAnimatedLoader({
    super.key,
    required this.isWebViewReady,
    required this.onFinished,
  });

  @override
  State<_InvoiceAnimatedLoader> createState() => _InvoiceAnimatedLoaderState();
}

class _InvoiceAnimatedLoaderState extends State<_InvoiceAnimatedLoader>
    with TickerProviderStateMixin {
  
  _LoaderPhase _phase = _LoaderPhase.preparing;

  late final AnimationController _docController;
  late final AnimationController _shimmerController;
  late final AnimationController _checkController;
  
  Timer? _sequenceTimer;

  @override
  void initState() {
    super.initState();
    _docController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _shimmerController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _checkController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    
    _docController.forward();
    
    _sequenceTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() => _phase = _LoaderPhase.shimmer);
      _shimmerController.repeat();
      
      _sequenceTimer = Timer(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _checkAndFinalize();
      });
    });
  }

  @override
  void didUpdateWidget(_InvoiceAnimatedLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isWebViewReady && !oldWidget.isWebViewReady) {
      _checkAndFinalize();
    }
  }

  void _checkAndFinalize() {
    if (_phase == _LoaderPhase.shimmer && widget.isWebViewReady) {
       _startFinalizing();
    }
  }

  void _startFinalizing() {
    if (_phase == _LoaderPhase.finalizing) return;
    _sequenceTimer?.cancel();
    setState(() => _phase = _LoaderPhase.finalizing);
    
    _shimmerController.stop();

    _checkController.forward().then((_) {
      _sequenceTimer = Timer(const Duration(milliseconds: 400), () {
        if (mounted) widget.onFinished();
      });
    });
  }

  @override
  void dispose() {
    _sequenceTimer?.cancel();
    _docController.dispose();
    _shimmerController.dispose();
    _checkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFCFAFF),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildDocumentVisual(),
            const SizedBox(height: 36),
            _buildText(),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentVisual() {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.96, end: 1.0).animate(CurvedAnimation(
        parent: _docController,
        curve: Curves.easeOutCubic,
      )),
      child: FadeTransition(
        opacity: _docController,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 120,
              height: 160,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentColor.withValues(alpha: 0.12),
                    blurRadius: 40,
                    spreadRadius: 10,
                  )
                ]
              ),
            ),
            
            if (_phase == _LoaderPhase.shimmer || _phase == _LoaderPhase.finalizing)
              _buildSparkles(),
            
            Container(
              width: 100,
              height: 140,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: AppTheme.accentColor.withValues(alpha: 0.05),
                    blurRadius: 2,
                  )
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(width: 40, height: 6, decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(3))),
                          const SizedBox(height: 14),
                          Container(width: double.infinity, height: 4, decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(2))),
                          const SizedBox(height: 8),
                          Container(width: double.infinity, height: 4, decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(2))),
                          const SizedBox(height: 8),
                          Container(width: 50, height: 4, decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(2))),
                          const Spacer(),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(width: 28, height: 6, decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(3))),
                          )
                        ],
                      ),
                    ),
                    if (_phase == _LoaderPhase.shimmer || _phase == _LoaderPhase.finalizing)
                      AnimatedBuilder(
                        animation: _shimmerController,
                        builder: (context, child) {
                          return Positioned.fill(
                            child: FractionalTranslation(
                              translation: Offset(-1.5 + (_shimmerController.value * 3.0), 0.0),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      AppTheme.accentColor.withValues(alpha: 0.15),
                                      Colors.transparent,
                                    ],
                                    stops: const [0.1, 0.5, 0.9],
                                  )
                                )
                              )
                            )
                          );
                        }
                      ),
                  ],
                ),
              ),
            ),
            
            if (_phase == _LoaderPhase.finalizing)
               Positioned(
                 bottom: -12,
                 right: -12,
                 child: ScaleTransition(
                   scale: CurvedAnimation(parent: _checkController, curve: Curves.easeOutBack),
                   child: FadeTransition(
                     opacity: _checkController,
                     child: Container(
                       width: 34,
                       height: 34,
                       decoration: const BoxDecoration(
                         color: AppTheme.accentColor,
                         shape: BoxShape.circle,
                       ),
                       child: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
                     )
                   )
                 )
               )
          ]
        )
      )
    );
  }

  Widget _buildSparkles() {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        final progress = _shimmerController.value;
        final opacity = (math.sin(progress * math.pi) * 0.8).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(top: -15, left: -25, child: Icon(Icons.auto_awesome_rounded, color: AppTheme.accentColor.withValues(alpha: 0.3), size: 18)),
              Positioned(bottom: 25, right: -30, child: Icon(Icons.star_rounded, color: AppTheme.accentColor.withValues(alpha: 0.25), size: 14)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildText() {
    String primary = "Preparing your\ninvoice...";
    String secondary = "Please wait a moment";

    if (_phase == _LoaderPhase.shimmer) {
      secondary = "Almost ready...";
    } else if (_phase == _LoaderPhase.finalizing) {
      primary = "Finalizing...";
      secondary = "Opening your invoice";
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Column(
        key: ValueKey(primary),
        children: [
          Text(
            primary,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.accentColor,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            secondary,
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: AppTheme.accentColor.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

