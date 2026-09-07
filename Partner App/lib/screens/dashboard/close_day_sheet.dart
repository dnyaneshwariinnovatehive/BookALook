import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/salon_closure_api.dart';
import '../../theme/app_theme.dart';

/// Emergency closure flow: pick the day, see exactly who it affects, then
/// confirm. Nothing is cancelled until the admin has seen the impact.
///
/// Returns true when a day was actually closed, so the caller can refresh.
class CloseDaySheet extends StatefulWidget {
  final String salonId;
  final DateTime initialDate;

  const CloseDaySheet({
    super.key,
    required this.salonId,
    required this.initialDate,
  });

  static Future<bool> show(
    BuildContext context, {
    required String salonId,
    DateTime? initialDate,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CloseDaySheet(
        salonId: salonId,
        initialDate: initialDate ?? DateTime.now(),
      ),
    );

    return result == true;
  }

  @override
  State<CloseDaySheet> createState() => _CloseDaySheetState();
}

class _CloseDaySheetState extends State<CloseDaySheet> {
  final _reasonController = TextEditingController();

  late DateTime _date;
  ClosurePreview? _preview;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Only today or later can be closed — the past cannot be un-served.
    final today = DateUtils.dateOnly(DateTime.now());
    final wanted = DateUtils.dateOnly(widget.initialDate);
    _date = wanted.isBefore(today) ? today : wanted;
    _loadPreview();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  String get _dateParam => DateFormat('yyyy-MM-dd').format(_date);

  Future<void> _loadPreview() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final preview = await SalonClosureApi.preview(widget.salonId, _dateParam);
      if (!mounted) return;
      setState(() {
        _preview = preview;
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateUtils.dateOnly(DateTime.now()),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked == null) return;
    setState(() => _date = picked);
    _loadPreview();
  }

  Future<void> _confirm() async {
    final preview = _preview;
    if (preview == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close this day?'),
        content: Text(
          preview.affectedCount == 0
              ? 'No bookings will be affected. The day will stop accepting new bookings.'
              : '${preview.affectedCount} booking(s) will be released and '
                  '${preview.customerCount} customer(s) notified that they can '
                  'rebook free of charge. This cannot be undone from here.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Close the day', style: TextStyle(color: AppTheme.lightDanger)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    try {
      final result = await SalonClosureApi.closeDay(
        widget.salonId,
        _dateParam,
        reason: _reasonController.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context, true);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          result.releasedCount == 0
              ? result.message
              : '${result.message} ${result.notifiedCount} customer(s) notified.',
        ),
        duration: const Duration(seconds: 5),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Nothing was changed'),
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            _buildHandle(),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 20),
                  _buildDateField(),
                  const SizedBox(height: 20),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    _buildError()
                  else ...[
                    _buildImpact(),
                    const SizedBox(height: 20),
                    _buildReasonField(),
                    const SizedBox(height: 12),
                    _buildAffectedList(),
                  ],
                ],
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() => Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  Widget _buildHeader() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Close the salon for a day',
              style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            'Everyone booked on this day is released and told they can rebook '
            'free of charge. Nothing they have paid is lost.',
            style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey.shade700),
          ),
        ],
      );

  Widget _buildDateField() => InkWell(
        onTap: _isSubmitting ? null : _pickDate,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(DateFormat('EEEE, d MMM yyyy').format(_date),
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600)),
              Icon(Icons.calendar_today, size: 18, color: AppTheme.accentColor),
            ],
          ),
        ),
      );

  Widget _buildError() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.lightDanger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(_error!, style: GoogleFonts.outfit(color: AppTheme.lightDanger)),
      );

  Widget _buildImpact() {
    final preview = _preview!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: preview.affectedCount == 0
            ? Colors.grey.shade100
            : AppTheme.lightWarning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (preview.alreadyClosed) ...[
            Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: AppTheme.lightWarning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('This day is already marked closed.',
                      style: GoogleFonts.outfit(
                          fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.lightWarning)),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Text(
            preview.affectedCount == 0
                ? 'No bookings on this day.'
                : '${preview.affectedCount} booking(s) will be released',
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          if (preview.affectedCount > 0) ...[
            const SizedBox(height: 8),
            _impactLine('${preview.customerCount} app customer(s) notified in-app and on WhatsApp'),
            if (preview.walkInCount > 0)
              _impactLine(
                  '${preview.walkInCount} walk-in(s) have no app account — call them yourself'),
            _impactLine(
                '₹${preview.advanceCarriedForward.toStringAsFixed(0)} of advances carried forward, not forfeited'),
          ],
          if (preview.untouchableCount > 0) ...[
            const SizedBox(height: 8),
            _impactLine(
                '${preview.untouchableCount} already in progress or completed — left untouched'),
          ],
        ],
      ),
    );
  }

  Widget _impactLine(String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•  '),
            Expanded(
              child: Text(text,
                  style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey.shade800)),
            ),
          ],
        ),
      );

  Widget _buildReasonField() => TextField(
        controller: _reasonController,
        enabled: !_isSubmitting,
        maxLength: 255,
        decoration: InputDecoration(
          labelText: 'Reason (shown to customers)',
          hintText: 'e.g. Burst water pipe, no power',
          border: const OutlineInputBorder(),
          counterText: '',
        ),
      );

  Widget _buildAffectedList() {
    final appointments = _preview!.appointments;
    if (appointments.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text('Who is affected',
            style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...appointments.map((apt) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(apt['start_time'] ?? '',
                        style: GoogleFonts.outfit(
                            fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.accentColor)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(apt['customer_name'] ?? 'Customer',
                            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(
                          [
                            apt['provider_name'] ?? 'Any staff',
                            if (apt['is_walk_in'] == true) 'walk-in — call them',
                          ].join(' · '),
                          style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  Text('₹${(double.tryParse('${apt['advance_paid'] ?? 0}') ?? 0).toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey.shade700)),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildFooter() {
    final canSubmit = !_isLoading && !_isSubmitting && _error == null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: canSubmit ? _confirm : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.lightDanger,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Close this day',
                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
