import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

class _SalonLocationScreenState extends State<SalonLocationScreen> {
  SalonLocation? _location;
  bool _loading = true;
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
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
        _error = 'Could not load your location.';
        _loading = false;
      });
    }
  }

  Future<void> _pinHere() async {
    setState(() => _saving = true);

    final position = await SalonLocationApi.devicePosition();

    if (!mounted) return;

    if (position == null) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'We could not read your location. Check that location is switched on '
          'and that BookALook is allowed to use it.',
        ),
      ));
      return;
    }

    try {
      final message = await SalonLocationApi.save(
        widget.salonId,
        position.latitude,
        position.longitude,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: Text('Salon location',
            style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error.isNotEmpty) _card(child: Text(_error)),
                _buildStatus(),
                const SizedBox(height: 16),
                _buildWhyItMatters(),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _pinHere,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.my_location),
                  label: Text(_saving
                      ? 'Reading your location…'
                      : _location?.isOwnerPinned == true
                          ? 'Update my pin'
                          : 'Pin my salon here'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accentColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Stand inside your salon before tapping, so the pin lands on '
                  'your door rather than the road.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                      fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
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
        ? 'Customers near you see you at the right distance.'
        : placed
            ? 'We have placed you in the middle of ${location?.cityName ?? 'your city'} '
                'until you pin your exact spot. Nearby customers may see other '
                'salons above you.'
            : 'Customers sorting by distance will see you last. Pin your salon '
                'to fix that.';

    return _card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
              pinnedByOwner
                  ? Icons.check_circle
                  : placed
                      ? Icons.adjust
                      : Icons.location_off,
              color: colour),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline,
                    style: GoogleFonts.outfit(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(detail,
                    style: GoogleFonts.outfit(
                        fontSize: 12.5,
                        height: 1.4,
                        color: Colors.grey.shade700)),
                if (placed) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${location!.latitude!.toStringAsFixed(5)}, '
                    '${location.longitude!.toStringAsFixed(5)}',
                    style: GoogleFonts.outfit(
                        fontSize: 11.5,
                        color: Colors.grey.shade500,
                        fontFeatures: const []),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhyItMatters() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Why this matters',
                style: GoogleFonts.outfit(
                    fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'When someone opens BookALook, salons are listed nearest first. '
              'Your exact position decides where you appear for the people '
              'standing closest to you — the ones most likely to walk in.',
              style: GoogleFonts.outfit(
                  fontSize: 12.5, height: 1.5, color: Colors.grey.shade700),
            ),
          ],
        ),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFECEAF2)),
        ),
        child: child,
      );
}
