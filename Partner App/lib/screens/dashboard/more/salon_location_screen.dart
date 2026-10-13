import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../services/salon_location_api.dart';
import '../../../theme/app_theme.dart';

/// Put the salon on the map.
///
/// Customers browsing are shown the nearest salons first. A salon the platform
/// cannot place sits at the middle of its city as a stand-in, which puts it
/// behind every salon on the same street that has pinned itself properly.
///
/// One tap, standing in the doorway, fixes that for good.
class SalonLocationScreen extends StatefulWidget {
  final String salonId;

  const SalonLocationScreen({super.key, required this.salonId});

  @override
  State<SalonLocationScreen> createState() => _SalonLocationScreenState();
}

class _SalonLocationScreenState extends State<SalonLocationScreen>
    with WidgetsBindingObserver {
  SalonLocation? _location;
  bool _loading = true;
  bool _saving = false;
  String _error = '';
  bool _waitingForSettingsReturn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Admin returned from Android device settings or app settings
      _onAppResumed();
    }
  }

  Future<void> _onAppResumed() async {
    if (_waitingForSettingsReturn) {
      _waitingForSettingsReturn = false;
      final hasPermission = await SalonLocationApi.isPermissionGranted();
      if (!mounted) return;
      if (hasPermission) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 4),
            content: Text(
              'Location permission detected! Tap "Pin my salon" to save your position.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _load() async {
    try {
      final location = await SalonLocationApi.fetch(widget.salonId);
      if (!mounted) return;
      setState(() {
        _location = location;
        _loading = false;
        _error = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your location. Please check your internet connection.';
        _loading = false;
      });
    }
  }

  /// Tapping the pin button initiates the workflow with context and confirmation.
  Future<void> _handlePinButtonTapped() async {
    if (_saving) return;

    // If salon already has a pin from owner, confirm they are at the salon before overwriting
    if (_location?.isOwnerPinned == true) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Update Salon Location?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: Text(
            'Are you currently inside or at the entrance of your salon?\n\n'
            'Your device\'s current GPS position will be set as your salon\'s public listing coordinates.',
            style: GoogleFonts.outfit(fontSize: 14, height: 1.4, color: Colors.grey.shade700),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey.shade600)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Yes, Update Pin', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    await _pinHere();
  }

  Future<void> _pinHere() async {
    setState(() => _saving = true);

    try {
      final position = await SalonLocationApi.requireDevicePosition();

      final message = await SalonLocationApi.save(
        widget.salonId,
        position.latitude,
        position.longitude,
      );

      HapticFeedback.mediumImpact();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w500, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
      await _load();
    } on LocationDisabledException {
      if (!mounted) return;
      _showGpsDisabledSheet();
    } on LocationPermissionDeniedException {
      if (!mounted) return;
      _showPermissionDeniedSheet();
    } on LocationPermissionPermanentlyDeniedException {
      if (!mounted) return;
      _showPermissionPermanentlyDeniedSheet();
    } catch (e) {
      if (!mounted) return;
      final errorMsg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          content: Text(errorMsg, style: GoogleFonts.outfit(color: Colors.white)),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: _pinHere,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Edge Case: Device GPS is turned off
  void _showGpsDisabledSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.location_off_rounded, size: 36, color: Colors.amber.shade800),
            ),
            const SizedBox(height: 18),
            Text(
              'Turn on Device Location (GPS)',
              style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Your phone\'s GPS is switched off. Please turn on Location Services so BookALook can pinpoint your salon\'s door.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey.shade700, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _waitingForSettingsReturn = true;
                SalonLocationApi.openLocationSettings();
              },
              icon: const Icon(Icons.settings, size: 18),
              label: Text('Open Location Settings',
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey.shade600)),
            ),
          ],
        ),
      ),
    );
  }

  /// Edge Case: Permission soft denial
  void _showPermissionDeniedSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.near_me_disabled_rounded, size: 36, color: Colors.blue.shade700),
            ),
            const SizedBox(height: 18),
            Text(
              'Location Permission Needed',
              style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'BookALook needs device location to pin your exact salon coordinates. Without this, customers searching nearby cannot discover your salon.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey.shade700, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _pinHere();
              },
              icon: const Icon(Icons.check, size: 18),
              label: Text('Allow Location Access',
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Not Now', style: GoogleFonts.outfit(color: Colors.grey.shade600)),
            ),
          ],
        ),
      ),
    );
  }

  /// Edge Case: Permanently denied ("Don't ask again")
  void _showPermissionPermanentlyDeniedSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_outline_rounded, size: 36, color: Colors.red.shade700),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Location Access is Disabled',
              style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Location permission was permanently disabled for BookALook. To update your salon\'s pin on the customer map:',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 13.5, color: Colors.grey.shade700, height: 1.4),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F7FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInstructionStep('1', 'Tap "Open App Settings" below'),
                  const SizedBox(height: 6),
                  _buildInstructionStep('2', 'Tap "Permissions" → "Location"'),
                  const SizedBox(height: 6),
                  _buildInstructionStep('3', 'Select "Allow only while using the app"'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _waitingForSettingsReturn = true;
                SalonLocationApi.openAppSettings();
              },
              icon: const Icon(Icons.settings, size: 18),
              label: Text('Open App Settings',
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey.shade600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionStep(String step, String text) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: AppTheme.accentColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              step,
              style: GoogleFonts.outfit(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: AppTheme.accentColor,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey.shade800),
          ),
        ),
      ],
    );
  }

  /// Open external Google Maps to verify pinned spot
  Future<void> _openGoogleMaps() async {
    final lat = _location?.latitude;
    final lng = _location?.longitude;
    if (lat == null || lng == null) return;

    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch Google Maps.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch Google Maps.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: Text(
          'Salon location',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            tooltip: 'Refresh location',
            icon: const Icon(Icons.refresh),
            onPressed: _loading || _saving ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error.isNotEmpty) ...[
                    _card(
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _error,
                              style: GoogleFonts.outfit(fontSize: 13, color: Colors.red.shade800),
                            ),
                          ),
                          TextButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _buildStatus(),
                  const SizedBox(height: 16),
                  _buildWhyItMatters(),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _handlePinButtonTapped,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.my_location),
                    label: Text(
                      _saving
                          ? 'Acquiring precise satellite fix…'
                          : _location?.isOwnerPinned == true
                              ? 'Update my pin'
                              : 'Pin my salon here',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accentColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Stand inside your salon before tapping, so the pin lands on '
                    'your door rather than the road.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatus() {
    final location = _location;
    final pinnedByOwner = location?.isOwnerPinned == true;
    final placed = location?.isPinned == true;

    final colour = pinnedByOwner
        ? Colors.green.shade700
        : placed
            ? AppTheme.lightWarning
            : AppTheme.lightDanger;

    final headline = pinnedByOwner
        ? 'Pinned to your salon'
        : placed
            ? 'Using your city centre'
            : 'Not on the map yet';

    final detail = pinnedByOwner
        ? 'Customers near you see your salon at the exact distance on the map.'
        : placed
            ? 'We have placed you in the middle of ${location?.cityName ?? 'your city'} '
                'until you pin your exact spot. Nearby customers may see other '
                'salons above you.'
            : 'Customers sorting by distance will see you last. Pin your salon '
                'to fix that.';

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                pinnedByOwner
                    ? Icons.check_circle
                    : placed
                        ? Icons.adjust
                        : Icons.location_off,
                color: colour,
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        height: 1.4,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    if (placed) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F3F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${location!.latitude!.toStringAsFixed(5)}, ${location.longitude!.toStringAsFixed(5)}',
                          style: GoogleFonts.robotoMono(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (placed) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 8),
            InkWell(
              onTap: _openGoogleMaps,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map_outlined, size: 18, color: AppTheme.accentColor),
                    const SizedBox(width: 8),
                    Text(
                      'Preview pin in Google Maps',
                      style: GoogleFonts.outfit(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accentColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.open_in_new, size: 14, color: AppTheme.accentColor),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWhyItMatters() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline, size: 20, color: AppTheme.accentColor),
                const SizedBox(width: 8),
                Text(
                  'Why this matters',
                  style: GoogleFonts.outfit(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'When someone opens BookALook, salons are listed nearest first. '
              'Your exact position decides where you appear for the people '
              'standing closest to you — the ones most likely to walk in.',
              style: GoogleFonts.outfit(
                fontSize: 13,
                height: 1.5,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFECEAF2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      );
}
