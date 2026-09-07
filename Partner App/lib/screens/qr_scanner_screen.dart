import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/check_in_api.dart';
import '../theme/app_theme.dart';
import 'check_in_confirm_sheet.dart';

/// Scans a customer's booking QR to start their appointment.
///
/// Scanning never commits anything on its own — it resolves the code and hands
/// off to [CheckInConfirmSheet], so a stray code in frame cannot start the
/// wrong session.
class QrScannerScreen extends StatefulWidget {
  final String salonId;

  /// Preselected when an admin opens the scanner from a specific booking.
  final String? expectedAppointmentId;

  const QrScannerScreen({
    Key? key,
    required this.salonId,
    this.expectedAppointmentId,
  }) : super(key: key);

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  bool _isBusy = false;
  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isBusy) return;

    final code = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);

    if (code == null) return;

    await _resolve(qrToken: code);
  }

  Future<void> _resolve({String? qrToken, String? appointmentId}) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);

    await _controller.stop();

    try {
      final target = await CheckInApi.resolve(
        widget.salonId,
        qrToken: qrToken,
        appointmentId: appointmentId,
      );

      if (!mounted) return;

      final started = await CheckInConfirmSheet.show(
        context,
        salonId: widget.salonId,
        target: target,
        qrToken: qrToken,
      );

      if (!mounted) return;

      if (started) {
        Navigator.pop(context, true);
        return;
      }

      // Cancelled — go back to scanning.
      setState(() => _isBusy = false);
      await _controller.start();
    } catch (e) {
      if (!mounted) return;
      await _showError(e.toString().replaceFirst('Exception: ', ''));
      if (!mounted) return;
      setState(() => _isBusy = false);
      await _controller.start();
    }
  }

  Future<void> _showError(String message) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Can't use that code"),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Try again')),
          ],
        ),
      );

  /// The customer's phone is dead, or the screen is cracked. Staff pick the
  /// booking from today's list instead; the session is recorded as a manual
  /// check-in rather than pretending a code was scanned.
  Future<void> _pickFromList() async {
    await _controller.stop();

    final appointmentId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PendingListSheet(salonId: widget.salonId),
    );

    if (!mounted) return;

    if (appointmentId == null) {
      await _controller.start();
      return;
    }

    await _resolve(appointmentId: appointmentId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Scan customer QR', style: GoogleFonts.outfit(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: _torchOn ? 'Turn torch off' : 'Turn torch on',
            icon: Icon(_torchOn ? Icons.flashlight_on : Icons.flashlight_off, color: Colors.white),
            onPressed: () async {
              await _controller.toggleTorch();
              setState(() => _torchOn = !_torchOn);
            },
          ),
          IconButton(
            tooltip: 'Switch camera',
            icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _buildCameraError(error),
          ),
          _buildReticle(),
          Positioned(
            top: 24,
            left: 24,
            right: 24,
            child: Text(
              'Point at the QR code in the customer’s Bookings tab',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14),
            ),
          ),
          Positioned(left: 20, right: 20, bottom: 32, child: _buildFallback()),
          if (_isBusy)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
        ],
      ),
    );
  }

  Widget _buildReticle() => IgnorePointer(
        child: Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white70, width: 3),
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      );

  Widget _buildCameraError(MobileScannerException error) => Container(
        color: Colors.black,
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              'The camera is not available.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              error.errorDetails?.message ??
                  'Check that camera permission is granted, then use the list below.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      );

  Widget _buildFallback() => SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isBusy ? null : _pickFromList,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.list_alt),
            label: Text("Can't scan? Pick from today's list",
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
        ),
      );
}

/// Today's bookings still waiting to be started or settled.
class _PendingListSheet extends StatefulWidget {
  final String salonId;

  const _PendingListSheet({required this.salonId});

  @override
  State<_PendingListSheet> createState() => _PendingListSheetState();
}

class _PendingListSheetState extends State<_PendingListSheet> {
  List<CheckInAppointment> _appointments = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await CheckInApi.pending(widget.salonId);
      if (!mounted) return;
      setState(() {
        _appointments = list;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Today's appointments",
                      style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    'Starting from here is recorded as a manual check-in.',
                    style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error!,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.outfit(color: AppTheme.lightDanger)),
                          ),
                        )
                      : _appointments.isEmpty
                          ? Center(
                              child: Text('Nothing left to check in today.',
                                  style: GoogleFonts.outfit(color: Colors.grey.shade600)),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: _appointments.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final apt = _appointments[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: apt.isInProgress
                                        ? AppTheme.accentColor.withValues(alpha: 0.15)
                                        : Colors.grey.shade200,
                                    child: Text(
                                      apt.startTime,
                                      style: GoogleFonts.outfit(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: apt.isInProgress
                                              ? AppTheme.accentColor
                                              : Colors.black54),
                                    ),
                                  ),
                                  title: Text(apt.customerName,
                                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                                  subtitle: Text(
                                    apt.isInProgress
                                        ? 'In progress · ${apt.servingProviderName ?? apt.bookedProviderName}'
                                        : 'Booked with ${apt.bookedProviderName}',
                                    style: GoogleFonts.outfit(fontSize: 12),
                                  ),
                                  trailing: Text('₹${apt.balanceAmount.toStringAsFixed(0)}',
                                      style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                                  onTap: () => Navigator.pop(context, apt.id),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
