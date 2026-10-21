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

  @visibleForTesting
  void seedForTest({
    List<dynamic>? enquiries,
    List<dynamic>? alerts,
    List<dynamic>? assignedSalons,
  }) {
    if (enquiries != null) _enquiries = enquiries;
    _isLoading = false;
    _firstLoad = false;
  }

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
      final enquiries = await CollaboratorApi.assignedEnquiries();

      if (!mounted) return;

      // Only salons whose onboarding has NOT been completed
      final incomplete = enquiries.where((e) {
        final salonStatus = e['salon_status']?.toString();
        if (salonStatus == 'active' || salonStatus == 'pending_approval') {
          return false;
        }
        return true;
      }).toList();

      if (silent && !_hasChanged(incomplete)) return;

      setState(() {
        _enquiries = incomplete;
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

  bool _hasChanged(List<dynamic> enquiries) =>
      enquiries.length != _enquiries.length;

  Future<void> _callOwner(String? phone, String salonName) async {
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: const Duration(milliseconds: 2500), content: Text('No phone number on file for $salonName.')),
      );
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: const Duration(milliseconds: 2500), 
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

    // Filter to only salons whose onboarding has not completed
    final incompleteEnquiries = _enquiries.where((e) {
      final salonStatus = e['salon_status']?.toString();
      if (salonStatus == 'active' || salonStatus == 'pending_approval') {
        return false;
      }
      return true;
    }).toList();

    if (incompleteEnquiries.isEmpty && pending.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _fetchEnquiries,
      color: AppTheme.accentColor,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_store.queuedCount > 0) _buildQueueBanner(),
          if (incompleteEnquiries.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                incompleteEnquiries.length == 1
                    ? '1 salon to onboard'
                    : '${incompleteEnquiries.length} salons to onboard',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            for (final enquiry in incompleteEnquiries)
              _buildEnquiryCard(Map<String, dynamic>.from(enquiry as Map)),
          ],
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
            onTap: (enquiry['phone']?.toString() ?? '').trim().isNotEmpty
                ? () => _callOwner(
                    enquiry['phone']?.toString(),
                    enquiry['salon_name']?.toString() ?? 'the salon',
                  )
                : null,
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

          Text(
            draft != null
                ? 'Draft saved ${_ago(draft.updatedAt)}'
                : 'Assigned ${_assignedOn(enquiry['assigned_at'])}',
            style: TextStyle(fontSize: 11.5, color: palette.textTertiary),
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


  Widget _detail(IconData icon, String text, {VoidCallback? onTap}) {
    final palette = context.colors;

    final row = Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: onTap != null ? AppTheme.accentColor : palette.textTertiary,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: onTap != null ? AppTheme.accentColor : palette.textSecondary,
                fontWeight: onTap != null ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
          if (onTap != null)
            Icon(Icons.call, size: 14, color: AppTheme.accentColor),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: row,
      );
    }
    return row;
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
