import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../services/salon_location_api.dart';
import '../../../theme/app_theme.dart';

/// The poster an owner prints and sticks in the window.
///
/// Drawn here rather than on the server: the owner needs a real PNG at print
/// resolution, and generating one server-side would mean an image library the
/// host may not have. The server owns the only part that must never vary — the
/// address the code carries.
///
/// It is a whole poster, not a bare square. A naked QR on a wall tells nobody
/// what it does; this one says the salon's name and what happens if you scan it.
class SalonQrScreen extends StatefulWidget {
  final String salonId;

  const SalonQrScreen({super.key, required this.salonId});

  @override
  State<SalonQrScreen> createState() => _SalonQrScreenState();
}

class _SalonQrScreenState extends State<SalonQrScreen> {
  /// Wraps the poster so it can be rasterised exactly as drawn.
  final GlobalKey _posterKey = GlobalKey();

  SalonQrCode? _qr;
  bool _loading = true;
  bool _exporting = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final qr = await SalonLocationApi.fetchQrCode(widget.salonId);
      if (!mounted) return;
      setState(() {
        _qr = qr;
        _loading = false;
        _error = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your QR code. Check your connection.';
        _loading = false;
      });
    }
  }

  /// Rasterise the poster at print resolution.
  ///
  /// 4x the logical size: a QR photographed off a phone screen scans fine at
  /// any size, but one printed at screen resolution turns to mush on paper.
  Future<Uint8List?> _renderPng() async {
    try {
      final boundary =
          _posterKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: 4.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Could not render the poster: $e');
      return null;
    }
  }

  Future<void> _share() async {
    setState(() => _exporting = true);

    try {
      final bytes = await _renderPng();

      if (bytes == null) throw Exception('render failed');

      final slug = _qr?.salonSlug ?? 'salon';
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/bookalook-$slug-qr.png');
      await file.writeAsBytes(bytes);

      if (!mounted) return;

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Scan to book at ${_qr?.salonName ?? 'our salon'} on BookALook',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not create the image. Please try again.'),
      ));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _copyLink() async {
    final url = _qr?.url;

    if (url == null) return;

    await Clipboard.setData(ClipboardData(text: url));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: Text('Your QR code',
            style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? _buildError()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildPoster(),
                    const SizedBox(height: 20),
                    _buildActions(),
                    const SizedBox(height: 20),
                    _buildExplainer(),
                  ],
                ),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(_error,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: Colors.grey.shade700)),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );

  /// The printable artwork itself.
  ///
  /// White background and generous quiet space around the code on purpose:
  /// both are what make a printed QR readable in poor light at an angle.
  Widget _buildPoster() => Center(
        child: RepaintBoundary(
          key: _posterKey,
          child: Container(
            width: 320,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            decoration: const BoxDecoration(color: Colors.white),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'BookALook',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.accentColor,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  _qr?.salonName ?? '',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    height: 1.2,
                  ),
                ),
                if ((_qr?.city ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _qr!.city!,
                    style: GoogleFonts.outfit(
                        fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
                const SizedBox(height: 22),
                QrImageView(
                  data: _qr?.url ?? '',
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                  // High correction: a poster in a salon gets scuffed, taped
                  // over at a corner, and photographed at an angle.
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 22),
                Text(
                  'Scan to book',
                  style: GoogleFonts.outfit(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Point your camera here to see our\nservices and book an appointment.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    height: 1.45,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildActions() => Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _exporting ? null : _share,
              icon: _exporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download),
              label: Text(_exporting ? 'Preparing…' : 'Save or share as PNG'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _copyLink,
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Copy link'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.accentColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      );

  Widget _buildExplainer() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFECEAF2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How to use it',
                style:
                    GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _step('1', 'Save the image and print it, or send it to a print shop.'),
            _step('2', 'Put it where customers wait — the counter, the window, '
                'the mirror.'),
            _step('3',
                'Anyone scanning with their camera or Google Lens goes straight '
                'to your page. If they have the app it opens there; if not, they '
                'see your salon on the web and can install it.'),
            const SizedBox(height: 10),
            SelectableText(
              _qr?.url ?? '',
              style: GoogleFonts.outfit(
                  fontSize: 11.5, color: Colors.grey.shade500),
            ),
          ],
        ),
      );

  Widget _step(String number, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.accentColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Text(number,
                  style: GoogleFonts.outfit(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accentColor)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: GoogleFonts.outfit(
                      fontSize: 12.5, height: 1.45, color: Colors.grey.shade700)),
            ),
          ],
        ),
      );
}
