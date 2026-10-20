import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../services/review_service.dart';
import '../theme/app_colors.dart';
import '../utils/bottom_clearance.dart';

/// Bottom sheet allowing customers to report a problem or file a complaint
/// regarding an appointment/visit.
class ComplaintBottomSheet extends StatefulWidget {
  /// The appointment being reported.
  final Map<String, dynamic> appointment;

  const ComplaintBottomSheet({super.key, required this.appointment});

  /// Shows the complaint bottom sheet. Returns true if a complaint was submitted.
  static Future<bool> show(
    BuildContext context,
    Map<String, dynamic> appointment,
  ) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (_) => ComplaintBottomSheet(appointment: appointment),
    );

    return result == true;
  }

  @override
  State<ComplaintBottomSheet> createState() => _ComplaintBottomSheetState();
}

class _ComplaintBottomSheetState extends State<ComplaintBottomSheet> {
  final _subject = TextEditingController();
  final _detail = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _detail.dispose();
    super.dispose();
  }

  String get _appointmentId =>
      (widget.appointment['id'] ?? widget.appointment['appointment_id'])
          ?.toString() ??
      '';

  String get _salonName {
    final salon = widget.appointment['salon'];
    if (salon is Map && salon['name'] != null) {
      return salon['name'].toString();
    }
    return widget.appointment['salon_name']?.toString() ?? 'the salon';
  }

  String get _dateLabel {
    final rawDate = widget.appointment['appointment_date']?.toString();
    if (rawDate == null || rawDate.isEmpty) return '';
    final parsed = DateTime.tryParse(rawDate);
    if (parsed == null) return rawDate;
    return DateFormat('d MMM yyyy').format(parsed);
  }

  Future<void> _submit() async {
    final subjectText = _subject.text.trim();
    final detailText = _detail.text.trim();

    if (subjectText.isEmpty) {
      setState(() => _error = 'Please enter a short subject for your report.');
      return;
    }
    if (detailText.isEmpty) {
      setState(() => _error = 'Please tell us what went wrong in detail.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final result = await ReviewService.submitComplaint(
        appointmentId: _appointmentId,
        subject: subjectText,
        description: detailText,
      );

      if (!mounted) return;
      Navigator.pop(context, true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ??
                'Thanks — your report has been submitted to the BookALook team.',
          ),
          backgroundColor: const Color(0xFF1B873F),
        ),
      );
    } on ReviewRefused catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not submit report. Please check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: sheetBottomInset(context)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              _buildHeader(),
              const SizedBox(height: 20),

              _buildPrivacyNotice(),
              const SizedBox(height: 18),

              _buildForm(),

              if (_error != null) ...[
                const SizedBox(height: 14),
                _buildError(),
              ],

              const SizedBox(height: 22),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: context.colors.dangerBg,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.report_problem_outlined,
            size: 28,
            color: context.colors.danger,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Report a Problem',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: context.colors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          [
            'Visit to $_salonName',
            if (_dateLabel.isNotEmpty) _dateLabel,
          ].join(' · '),
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 13,
            color: context.colors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildPrivacyNotice() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.shield_outlined,
            size: 18,
            color: context.colors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your report is sent privately to the BookALook support team to review with the salon. It will not be shown as a public review.',
              style: GoogleFonts.outfit(
                fontSize: 12,
                height: 1.35,
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Subject',
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: context.colors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _subject,
          maxLength: 150,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'e.g. Staff behaviour, billing issue, poor service',
            hintStyle: GoogleFonts.outfit(
              fontSize: 13,
              color: context.colors.textTertiary,
            ),
            counterText: '',
            filled: true,
            fillColor: context.colors.surfaceMuted,
            contentPadding: const EdgeInsets.all(14),
            border: _border(context.colors.border),
            enabledBorder: _border(context.colors.border),
            focusedBorder: _border(context.colors.danger),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Tell us what happened',
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: context.colors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _detail,
          maxLines: 4,
          maxLength: 2000,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Please describe the issue in detail so our team can investigate...',
            hintStyle: GoogleFonts.outfit(
              fontSize: 13,
              color: context.colors.textTertiary,
            ),
            counterText: '',
            filled: true,
            fillColor: context.colors.surfaceMuted,
            contentPadding: const EdgeInsets.all(14),
            border: _border(context.colors.border),
            enabledBorder: _border(context.colors.border),
            focusedBorder: _border(context.colors.danger),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.dangerBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 17, color: context.colors.danger),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _error!,
              style: GoogleFonts.outfit(
                fontSize: 12.5,
                height: 1.35,
                color: context.colors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: context.colors.danger,
              foregroundColor: Colors.white,
              disabledBackgroundColor: context.colors.border,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _submitting
                ? const SizedBox(
                    height: 19,
                    width: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'Submit Report',
                    style: GoogleFonts.outfit(
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context, false),
          child: Text(
            'Cancel',
            style: GoogleFonts.outfit(
              fontSize: 13.5,
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _border(Color colour) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colour),
      );
}
