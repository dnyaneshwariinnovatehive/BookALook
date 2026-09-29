import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/onboarding_draft.dart';
import '../../../services/collaborator_api.dart';
import '../../../services/collaborator_badges.dart';
import '../../../services/onboarding_draft_store.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/collaborator/collaborator_card.dart';
import '../../../widgets/collaborator/collaborator_chip.dart';
import '../../../widgets/collaborator/collaborator_empty_state.dart';
import '../../../widgets/collaborator/collaborator_skeleton.dart';
import '../../../widgets/collaborator/collaborator_thumb.dart';
import '../../collaborator/onboard_salon_screen.dart';

/// The collaborator's worklist: salons SuperAdmin has handed them to onboard.
///
/// A card here is one of three things — a fresh assignment, a visit already
/// half typed up and sitting on the device, or a salon SuperAdmin sent back for
/// correction. They look different because they need different things done to
/// them.
class CollaboratorAssignedTab extends StatefulWidget {
  /// Counts the bottom navigation badges are drawn from. Null when the tab is
  /// used standalone.
  final CollaboratorBadges? badges;

  const CollaboratorAssignedTab({super.key, this.badges});

  @override
  State<CollaboratorAssignedTab> createState() =>
      CollaboratorAssignedTabState();
}

/// Public so the shell can ask for a refresh when the tab is re-selected.
class CollaboratorAssignedTabState extends State<CollaboratorAssignedTab> {
  final _store = OnboardingDraftStore.instance;

  bool _isLoading = true;
  bool _firstLoad = true;
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

  /// Whether the collaborator is actually looking at this tab.
  ///
  /// The shell keeps every tab alive in an [IndexedStack], so "mounted" no
  /// longer implies "visible". Without this the poll below would keep firing
  /// all session the moment anyone opened another tab — three HTTP requests
  /// every 20 seconds, on a battery, for a list nobody is reading. The previous
  /// shell rebuilt tabs on every switch, which stopped the timer as a side
  /// effect of throwing the State away; moving to an [IndexedStack] takes that
  /// away, so the timer is gated explicitly instead.
  ///
  /// Starts false rather than true. The shell's first build runs before this
  /// State exists, so an initial true would let [_bootstrap] start the timer for
  /// a tab sitting hidden behind Home, with nothing to stop it until some later
  /// rebuild happened to pass back through [setActive]. Opting in has to be the
  /// default direction.
  bool _isActive = false;

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

  /// Whether the 20-second poll is currently armed. Exposed for tests, which
  /// are the only way to catch it running on a tab nobody is looking at.
  @visibleForTesting
  bool get isPolling => _poll != null;

  /// Called by the shell whenever this tab gains or loses visibility.
  void setActive(bool active) {
    if (_isActive == active) return;
    _isActive = active;

    if (active) {
      _startPolling();
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  /// Re-reads the worklist. Called by the shell when the tab is re-selected,
  /// and again after onboarding so a submitted salon leaves the list at once.
  Future<void> reload() => _fetchEnquiries();

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    await _store.load();
    await _fetchEnquiries();

    // Keeps the list live while the collaborator is looking at it. Quiet
    // refreshes: no spinner, and the list only moves if something changed.
    if (_isActive) _startPolling();
  }

  void _startPolling() {
    _poll ??= Timer.periodic(
      _pollInterval,
      (_) => _fetchEnquiries(silent: true),
    );
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

      widget.badges?.reportAssigned(_enquiries.length);
    } catch (e) {
      debugPrint('Error fetching assigned work: $e');
    } finally {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _firstLoad = false;
        });
      }
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
        SnackBar(
          content: Text('Could not start a call. The number is $phone.'),
        ),
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
    if (_firstLoad && _isLoading) {
      return const CollaboratorCardSkeleton(count: 3);
    }

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
      color: AppTheme.accentColor,
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
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: context.colors.textPrimary,
                ),
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
  Widget _buildAssignedSalonsSection() {
    final palette = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.how_to_reg_outlined, size: 17, color: palette.info),
            const SizedBox(width: 8),
            Text(
              _assignedSalons.length == 1
                  ? '1 salon in your care'
                  : '${_assignedSalons.length} salons in your care',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Already registered by their owners. SuperAdmin put you on them — no '
          'onboarding needed.',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.4,
            color: palette.textTertiary,
          ),
        ),
        const SizedBox(height: 12),
        for (final raw in _assignedSalons)
          _buildAssignedSalonCard(Map<String, dynamic>.from(raw as Map)),
      ],
    );
  }

  Widget _buildAssignedSalonCard(Map<String, dynamic> salon) {
    final needsPlan = salon['needs_plan'] == true;
    final daysLeft = salon['days_left'] as int?;
    final noServices = (salon['services_count'] ?? 0) == 0;
    final palette = context.colors;

    return CollaboratorCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CollaboratorThumb(url: salon['cover_photo_url']?.toString()),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      salon['name']?.toString() ?? 'Salon',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [salon['address'], salon['city']]
                          .where((p) => p != null && p.toString().isNotEmpty)
                          .join(', '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${salon['owner_name'] ?? 'Owner'} · '
                      '${salon['services_count'] ?? 0} '
                      '${salon['services_count'] == 1 ? 'service' : 'services'}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: palette.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // The two things actually worth a call on a self-registered salon.
          if (needsPlan ||
              noServices ||
              (daysLeft != null && daysLeft <= 7)) ...[
            const SizedBox(height: 11),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (needsPlan)
                  CollaboratorChip(
                    label: 'No plan chosen yet',
                    colour: palette.warning,
                  ),
                if (daysLeft != null && daysLeft <= 7)
                  CollaboratorChip(
                    label: daysLeft <= 0
                        ? 'Plan ends today'
                        : 'Plan ends in $daysLeft days',
                    colour: palette.danger,
                  ),
                if (noServices)
                  CollaboratorChip(
                    label: 'Menu is empty',
                    colour: palette.info,
                  ),
              ],
            ),
          ] else if (salon['plan_name'] != null) ...[
            const SizedBox(height: 11),
            CollaboratorChip(
              label: 'On ${salon['plan_name']}',
              colour: palette.success,
            ),
          ],

          const SizedBox(height: 12),
          Divider(height: 1, color: palette.border),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _callOwner(
                salon['owner_phone']?.toString(),
                salon['name']?.toString() ?? 'the salon',
              ),
              icon: const Icon(Icons.call, size: 16),
              label: Text(
                'Call ${salon['owner_name'] ?? 'owner'}',
                style: const TextStyle(fontSize: 12.5),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.accentColor,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Expiry alerts for salons this collaborator already onboarded.
  ///
  /// They cannot renew anything — only the owner can pay — so the one action
  /// offered is the call to the owner they already met.
  Widget _buildAlertsSection() {
    final palette = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.notifications_active_outlined,
              size: 17,
              color: palette.warning,
            ),
            const SizedBox(width: 8),
            Text(
              _alerts.length == 1
                  ? '1 salon needs a call'
                  : '${_alerts.length} salons need a call',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final raw in _alerts)
          _buildAlertCard(Map<String, dynamic>.from(raw as Map)),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    final lapsed = alert['severity'] == 'lapsed';
    final palette = context.colors;
    final colour = lapsed ? palette.danger : palette.warning;

    return CollaboratorCard(
      padding: const EdgeInsets.all(14),
      color: lapsed ? palette.dangerBg : palette.warningBg,
      borderColor: colour.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                lapsed ? Icons.wifi_off_rounded : Icons.timer_outlined,
                size: 18,
                color: colour,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  alert['message']?.toString() ?? '',
                  style: TextStyle(fontSize: 13, height: 1.4, color: colour),
                ),
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
                  style: TextStyle(
                    fontSize: 11.5,
                    color: palette.textSecondary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _callOwner(
                  alert['owner_phone']?.toString(),
                  alert['salon_name']?.toString() ?? 'the salon',
                ),
                icon: const Icon(Icons.call, size: 15),
                label: const Text(
                  'Call owner',
                  style: TextStyle(fontSize: 12.5),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: colour,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNothingAssignedNote() {
    final palette = context.colors;

    return CollaboratorCard(
      radius: 12,
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 18, color: palette.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No salons waiting to be onboarded.',
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  /// Finished drafts that have not reached the server yet. Shown as a fact, not
  /// an error — the collaborator has done their part.
  Widget _buildQueueBanner() {
    final palette = context.colors;
    final warning = palette.warning;

    return CollaboratorCard(
      padding: const EdgeInsets.all(14),
      color: palette.warningBg,
      borderColor: warning.withValues(alpha: 0.3),
      child: Row(
        children: [
          if (_store.isSyncing)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: warning),
            )
          else
            Icon(Icons.cloud_upload_outlined, size: 20, color: warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _store.isSyncing
                  ? 'Sending ${_store.queuedCount} finished ${_store.queuedCount == 1 ? 'salon' : 'salons'}…'
                  : '${_store.queuedCount} finished ${_store.queuedCount == 1 ? 'salon is' : 'salons are'} '
                        'waiting for a connection. They will send themselves.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: warning),
            ),
          ),
          if (!_store.isSyncing)
            TextButton(
              onPressed: _store.sync,
              style: TextButton.styleFrom(
                foregroundColor: warning,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Retry', style: TextStyle(fontSize: 12.5)),
            ),
        ],
      ),
    );
  }

  Widget _buildEnquiryCard(Map<String, dynamic> enquiry) {
    final id = enquiry['id'].toString();
    final draft = _store.forEnquiry(id);
    final needsCorrection = enquiry['needs_correction'] == true;
    final palette = context.colors;

    return CollaboratorCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  enquiry['salon_name']?.toString() ?? 'Unknown salon',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              _statusChip(needsCorrection, draft),
            ],
          ),
          const SizedBox(height: 12),

          _detail(
            Icons.person_outline,
            enquiry['owner_name']?.toString() ?? 'Unknown owner',
          ),
          _detail(
            Icons.phone_outlined,
            enquiry['phone']?.toString() ?? 'No phone',
          ),
          _detail(
            Icons.location_city_outlined,
            enquiry['city']?.toString() ?? 'Unknown city',
          ),

          if ((enquiry['message']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: palette.surfaceMuted,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                enquiry['message'].toString(),
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: palette.textSecondary,
                ),
              ),
            ),
          ],

          if (needsCorrection &&
              (enquiry['rejection_reason']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: palette.dangerBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 16, color: palette.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'SuperAdmin sent this back: ${enquiry['rejection_reason']}',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: palette.danger,
                      ),
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
              style: TextStyle(fontSize: 12, color: palette.danger),
            ),
          ],

          const SizedBox(height: 14),
          Divider(height: 1, color: palette.border),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: Text(
                  draft != null
                      ? 'Draft saved ${_ago(draft.updatedAt)}'
                      : 'Assigned ${_assignedOn(enquiry['assigned_at'])}',
                  style: TextStyle(fontSize: 11.5, color: palette.textTertiary),
                ),
              ),
              if (draft != null)
                // Discarding deletes the photos too, so it is styled as the
                // destructive action it is rather than the quiet grey link it
                // used to be, sitting right next to the primary button.
                OutlinedButton.icon(
                  onPressed: () => _confirmDiscard(id),
                  icon: const Icon(Icons.delete_outline, size: 15),
                  label: const Text(
                    'Discard',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.danger,
                    backgroundColor: palette.dangerBg,
                    side: BorderSide(
                      color: palette.danger.withValues(alpha: 0.35),
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
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
                foregroundColor: palette.onAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(bool needsCorrection, OnboardingDraft? draft) {
    final palette = context.colors;

    final (label, colour) = switch (true) {
      _ when needsCorrection => ('Needs fixing', palette.danger),
      _ when draft != null && draft.isComplete => (
        'Ready to send',
        palette.warning,
      ),
      _ when draft != null => ('In progress', palette.info),
      _ => ('Assigned', AppTheme.accentColor),
    };

    return CollaboratorChip(label: label, colour: colour);
  }

  Future<void> _confirmDiscard(String enquiryId) async {
    final palette = context.colors;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard this draft?'),
        content: const Text(
          'Everything typed in for this salon, including its photos, will be deleted '
          'from this device. The assignment stays on your list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          // A filled danger button, not a flat link. The dialog it opens is the
          // only thing standing between a collaborator and a lost afternoon of
          // photos, and it should not look like a menu item.
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.danger,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (confirmed == true) await _store.discard(enquiryId);
  }

  Widget _detail(IconData icon, String text) {
    final palette = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(icon, size: 16, color: palette.textTertiary),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  static String _assignedOn(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    return parsed == null
        ? 'recently'
        : 'on ${DateFormat('d MMM yyyy').format(parsed.toLocal())}';
  }

  static String _ago(DateTime when) {
    final gap = DateTime.now().difference(when);

    if (gap.inMinutes < 1) return 'just now';
    if (gap.inHours < 1) return '${gap.inMinutes} min ago';
    if (gap.inDays < 1) return '${gap.inHours}h ago';
    return 'on ${DateFormat('d MMM').format(when)}';
  }

  Widget _buildEmptyState() => CollaboratorEmptyState(
    icon: Icons.inbox_outlined,
    title: 'No assigned salons',
    body:
        'Salons reach you through the enquiry form on the website. Once '
        'SuperAdmin assigns one to you, it appears here ready to onboard.',
    actionLabel: 'Check again',
    onAction: _fetchEnquiries,
  );
}
