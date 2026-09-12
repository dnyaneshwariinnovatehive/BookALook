import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/onboarding_draft.dart';
import '../../../services/collaborator_api.dart';
import '../../../services/onboarding_draft_store.dart';
import '../../collaborator/onboard_salon_screen.dart';

/// The collaborator's worklist: salons SuperAdmin has handed them to onboard.
///
/// A card here is one of three things — a fresh assignment, a visit already
/// half typed up and sitting on the device, or a salon SuperAdmin sent back for
/// correction. They look different because they need different things done to
/// them.
class CollaboratorAssignedTab extends StatefulWidget {
  const CollaboratorAssignedTab({super.key});

  @override
  State<CollaboratorAssignedTab> createState() => _CollaboratorAssignedTabState();
}

class _CollaboratorAssignedTabState extends State<CollaboratorAssignedTab> {
  final _store = OnboardingDraftStore.instance;

  bool _isLoading = true;
  List<dynamic> _enquiries = [];

  /// Salons this collaborator onboarded whose plan is running out. They sit
  /// here as well as on Home because this is the tab a collaborator lives in.
  List<dynamic> _alerts = [];

  /// Existing salons SuperAdmin handed over from the directory. Not onboarding
  /// work — these already exist and have owners.
  List<dynamic> _assignedSalons = [];

  /// SuperAdmin assigns from a web page the collaborator cannot see, so a new
  /// assignment has to turn up on its own rather than waiting for a pull.
  Timer? _poll;
  static const _pollInterval = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    await _store.load();
    await _fetchEnquiries();

    // Keeps the list live while the collaborator is looking at it. Quiet
    // refreshes: no spinner, and the list only moves if something changed.
    _poll ??= Timer.periodic(_pollInterval, (_) => _fetchEnquiries(silent: true));
  }

  Future<void> _fetchEnquiries({bool silent = false}) async {
    // Opening the list is a good moment to find out whether the phone has
    // signal again, and anything queued should go now rather than wait for the
    // timer.
    unawaited(_store.sync());

    try {
      final results = await Future.wait([
        CollaboratorApi.assignedEnquiries(),
        CollaboratorApi.alerts(),
        CollaboratorApi.assignedSalons(),
      ]);

      if (!mounted) return;

      // A silent poll that found nothing new must not rebuild the list under
      // the collaborator's thumb while they are reading it.
      if (silent && !_hasChanged(results)) return;

      setState(() {
        _enquiries = results[0];
        _alerts = results[1];
        _assignedSalons = results[2];
      });
    } catch (e) {
      debugPrint('Error fetching assigned work: $e');
    } finally {
      if (mounted && !silent) setState(() => _isLoading = false);
    }
  }

  bool _hasChanged(List<List<dynamic>> results) =>
      results[0].length != _enquiries.length ||
      results[1].length != _alerts.length ||
      results[2].length != _assignedSalons.length;

  Future<void> _callOwner(String? phone, String salonName) async {
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No phone number on file for $salonName.')),
      );
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start a call. The number is $phone.')),
      );
    }
  }

  Future<void> _openOnboarding(Map<String, dynamic> enquiry) async {
    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => OnboardSalonScreen(enquiry: enquiry)),
    );

    if (submitted == true) await _fetchEnquiries();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    // Drafts for assignments the server no longer lists (already submitted from
    // another device, or reassigned) would otherwise be invisible forever.
    final pending = _store.pending;

    if (_enquiries.isEmpty &&
        pending.isEmpty &&
        _alerts.isEmpty &&
        _assignedSalons.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _fetchEnquiries,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_store.queuedCount > 0) _buildQueueBanner(),
          if (_alerts.isNotEmpty) _buildAlertsSection(),
          if (_enquiries.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _enquiries.length == 1
                    ? '1 salon to onboard'
                    : '${_enquiries.length} salons to onboard',
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
              ),
            ),
            for (final enquiry in _enquiries)
              _buildEnquiryCard(Map<String, dynamic>.from(enquiry as Map)),
          ] else if (_alerts.isEmpty && _assignedSalons.isEmpty)
            _buildNothingAssignedNote(),

          if (_assignedSalons.isNotEmpty) _buildAssignedSalonsSection(),
        ],
      ),
    );
  }

  /// Salons SuperAdmin assigned straight from the directory.
  ///
  /// These registered themselves from the partner app, so there is nothing to
  /// onboard — they already exist and already have an owner. What they need is
  /// somebody to call, which is why the card leads with the owner and the plan
  /// rather than a form.
  Widget _buildAssignedSalonsSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.how_to_reg_outlined, size: 17, color: AppTheme.lightInfo),
              const SizedBox(width: 8),
              Text(
                _assignedSalons.length == 1
                    ? '1 salon in your care'
                    : '${_assignedSalons.length} salons in your care',
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Already registered by their owners. SuperAdmin put you on them — no '
            'onboarding needed.',
            style: TextStyle(fontSize: 11.5, height: 1.4, color: AppTheme.lightTextLight),
          ),
          const SizedBox(height: 12),
          for (final raw in _assignedSalons)
            _buildAssignedSalonCard(Map<String, dynamic>.from(raw as Map)),
        ],
      );

  Widget _buildAssignedSalonCard(Map<String, dynamic> salon) {
    final needsPlan = salon['needs_plan'] == true;
    final daysLeft = salon['days_left'] as int?;
    final noServices = (salon['services_count'] ?? 0) == 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSalonThumb(salon['cover_photo_url']?.toString()),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(salon['name']?.toString() ?? 'Salon',
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Text(
                      [salon['address'], salon['city']]
                          .where((p) => p != null && p.toString().isNotEmpty)
                          .join(', '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppTheme.lightTextBody),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${salon['owner_name'] ?? 'Owner'} · '
                      '${salon['services_count'] ?? 0} '
                      '${salon['services_count'] == 1 ? 'service' : 'services'}',
                      style: const TextStyle(fontSize: 11.5, color: AppTheme.lightTextLight),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // The two things actually worth a call on a self-registered salon.
          if (needsPlan || noServices || (daysLeft != null && daysLeft <= 7)) ...[
            const SizedBox(height: 11),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (needsPlan)
                  _todoChip('No plan chosen yet', AppTheme.lightWarning),
                if (daysLeft != null && daysLeft <= 7)
                  _todoChip(
                    daysLeft <= 0 ? 'Plan ends today' : 'Plan ends in $daysLeft days',
                    AppTheme.lightDanger,
                  ),
                if (noServices) _todoChip('Menu is empty', AppTheme.lightInfo),
              ],
            ),
          ] else if (salon['plan_name'] != null) ...[
            const SizedBox(height: 11),
            _todoChip('On ${salon['plan_name']}', AppTheme.lightSuccess),
          ],

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _callOwner(
                salon['owner_phone']?.toString(),
                salon['name']?.toString() ?? 'the salon',
              ),
              icon: const Icon(Icons.call, size: 16),
              label: Text('Call ${salon['owner_name'] ?? 'owner'}',
                  style: const TextStyle(fontSize: 12.5)),
              style: TextButton.styleFrom(
                  foregroundColor: AppTheme.accentColor,
                  visualDensity: VisualDensity.compact),
            ),
          ),
        ],
      ),
    );
  }

  Widget _todoChip(String label, Color colour) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: colour)),
      );

  Widget _buildSalonThumb(String? url) {
    const size = 56.0;

    if (url == null || url.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppTheme.lightAccentSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.storefront_outlined, size: 22, color: AppTheme.accentColor),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          color: AppTheme.lightAccentSoft,
          child: const Icon(Icons.storefront_outlined, size: 22, color: AppTheme.accentColor),
        ),
      ),
    );
  }

  /// Expiry alerts for salons this collaborator already onboarded.
  ///
  /// They cannot renew anything — only the owner can pay — so the one action
  /// offered is the call to the owner they already met.
  Widget _buildAlertsSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_outlined,
                  size: 17, color: AppTheme.lightWarning),
              const SizedBox(width: 8),
              Text(
                _alerts.length == 1
                    ? '1 salon needs a call'
                    : '${_alerts.length} salons need a call',
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final raw in _alerts) _buildAlertCard(Map<String, dynamic>.from(raw as Map)),
          const SizedBox(height: 10),
        ],
      );

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    final lapsed = alert['severity'] == 'lapsed';
    final colour = lapsed ? AppTheme.lightDanger : AppTheme.lightWarning;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: lapsed ? AppTheme.lightDangerBg : AppTheme.lightWarningBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colour.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(lapsed ? Icons.wifi_off_rounded : Icons.timer_outlined,
                  size: 18, color: colour),
              const SizedBox(width: 10),
              Expanded(
                child: Text(alert['message']?.toString() ?? '',
                    style: TextStyle(fontSize: 13, height: 1.4, color: colour)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${alert['owner_name'] ?? 'Owner'}'
                  '${alert['city'] != null ? ' · ${alert['city']}' : ''}',
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.lightTextBody),
                ),
              ),
              TextButton.icon(
                onPressed: () => _callOwner(
                  alert['owner_phone']?.toString(),
                  alert['salon_name']?.toString() ?? 'the salon',
                ),
                icon: const Icon(Icons.call, size: 15),
                label: const Text('Call owner', style: TextStyle(fontSize: 12.5)),
                style: TextButton.styleFrom(
                    foregroundColor: colour, visualDensity: VisualDensity.compact),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNothingAssignedNote() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.lightBorder),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline, size: 18, color: AppTheme.lightSuccess),
            SizedBox(width: 10),
            Expanded(
              child: Text('No salons waiting to be onboarded.',
                  style: TextStyle(fontSize: 13, color: AppTheme.lightTextBody)),
            ),
          ],
        ),
      );

  /// Finished drafts that have not reached the server yet. Shown as a fact, not
  /// an error — the collaborator has done their part.
  Widget _buildQueueBanner() => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.lightWarningBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.lightWarning.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            if (_store.isSyncing)
              const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.lightWarning),
              )
            else
              const Icon(Icons.cloud_upload_outlined, size: 20, color: AppTheme.lightWarning),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _store.isSyncing
                    ? 'Sending ${_store.queuedCount} finished ${_store.queuedCount == 1 ? 'salon' : 'salons'}…'
                    : '${_store.queuedCount} finished ${_store.queuedCount == 1 ? 'salon is' : 'salons are'} '
                        'waiting for a connection. They will send themselves.',
                style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppTheme.lightWarning),
              ),
            ),
            if (!_store.isSyncing)
              TextButton(
                onPressed: _store.sync,
                style: TextButton.styleFrom(
                    foregroundColor: AppTheme.lightWarning, visualDensity: VisualDensity.compact),
                child: const Text('Retry', style: TextStyle(fontSize: 12.5)),
              ),
          ],
        ),
      );

  Widget _buildEnquiryCard(Map<String, dynamic> enquiry) {
    final id = enquiry['id'].toString();
    final draft = _store.forEnquiry(id);
    final needsCorrection = enquiry['needs_correction'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    enquiry['salon_name']?.toString() ?? 'Unknown salon',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
                _statusChip(needsCorrection, draft),
              ],
            ),
            const SizedBox(height: 12),

            _detail(Icons.person_outline, enquiry['owner_name']?.toString() ?? 'Unknown owner'),
            _detail(Icons.phone_outlined, enquiry['phone']?.toString() ?? 'No phone'),
            _detail(Icons.location_city_outlined, enquiry['city']?.toString() ?? 'Unknown city'),

            if ((enquiry['message']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.lightBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  enquiry['message'].toString(),
                  style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppTheme.lightTextBody),
                ),
              ),
            ],

            if (needsCorrection && (enquiry['rejection_reason']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.lightDangerBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: AppTheme.lightDanger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'SuperAdmin sent this back: ${enquiry['rejection_reason']}',
                        style: const TextStyle(
                            fontSize: 12, height: 1.4, color: AppTheme.lightDanger),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (draft?.lastError != null) ...[
              const SizedBox(height: 10),
              Text(
                'Last submission was refused: ${draft!.lastError}',
                style: const TextStyle(fontSize: 12, color: AppTheme.lightDanger),
              ),
            ],

            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: Text(
                    draft != null
                        ? 'Draft saved ${_ago(draft.updatedAt)}'
                        : 'Assigned ${_assignedOn(enquiry['assigned_at'])}',
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.lightTextLight),
                  ),
                ),
                if (draft != null)
                  TextButton(
                    onPressed: () => _confirmDiscard(id),
                    style: TextButton.styleFrom(
                        foregroundColor: AppTheme.lightTextBody,
                        visualDensity: VisualDensity.compact),
                    child: const Text('Discard', style: TextStyle(fontSize: 12.5)),
                  ),
              ],
            ),

            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openOnboarding(enquiry),
                icon: Icon(
                  needsCorrection
                      ? Icons.edit_outlined
                      : draft != null
                          ? Icons.play_arrow_rounded
                          : Icons.rocket_launch_outlined,
                  size: 19,
                ),
                label: Text(
                  needsCorrection
                      ? 'Fix and resubmit'
                      : draft != null
                          ? 'Continue onboarding'
                          : 'Start onboarding',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: AppTheme.accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(bool needsCorrection, OnboardingDraft? draft) {
    final (label, colour) = switch (true) {
      _ when needsCorrection => ('Needs fixing', AppTheme.lightDanger),
      _ when draft != null && draft.isComplete => ('Ready to send', AppTheme.lightWarning),
      _ when draft != null => ('In progress', AppTheme.lightInfo),
      _ => ('Assigned', AppTheme.accentColor),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(color: colour, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }

  Future<void> _confirmDiscard(String enquiryId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard this draft?'),
        content: const Text(
            'Everything typed in for this salon, including its photos, will be deleted '
            'from this device. The assignment stays on your list.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.lightDanger),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (confirmed == true) await _store.discard(enquiryId);
  }

  Widget _detail(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.lightTextLight),
            const SizedBox(width: 9),
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 13, color: AppTheme.lightTextBody)),
            ),
          ],
        ),
      );

  static String _assignedOn(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    return parsed == null ? 'recently' : 'on ${DateFormat('d MMM yyyy').format(parsed.toLocal())}';
  }

  static String _ago(DateTime when) {
    final gap = DateTime.now().difference(when);

    if (gap.inMinutes < 1) return 'just now';
    if (gap.inHours < 1) return '${gap.inMinutes} min ago';
    if (gap.inDays < 1) return '${gap.inHours}h ago';
    return 'on ${DateFormat('d MMM').format(when)}';
  }

  Widget _buildEmptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.assignment_ind_outlined, size: 72, color: AppTheme.lightTextLight),
              const SizedBox(height: 20),
              const Text('No assigned salons',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text(
                'Salons reach you through the enquiry form on the website. Once '
                'SuperAdmin assigns one to you, it appears here ready to onboard.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.5, color: AppTheme.lightTextBody),
              ),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: _fetchEnquiries,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Check again'),
              ),
            ],
          ),
        ),
      );
}
