import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/onboarding_draft.dart';
import 'collaborator_api.dart';

/// Drafts on the device, and getting them to the server eventually.
///
/// A collaborator fills a salon in wherever the salon happens to be, which is
/// regularly somewhere with no usable signal. So nothing they type is ever sent
/// as they type it: the draft is written to disk on every change, and sending
/// is a separate background concern that keeps trying.
///
/// "Back online" is not something this app can be told — it has no connectivity
/// plugin — so it is inferred the only way that is actually reliable: by trying
/// and seeing. Retries happen when the app comes back to the foreground, when
/// the collaborator opens their lists, and on a slow timer in between. A failed
/// attempt costs one dead socket; a missed reconnection would cost the whole
/// visit.
class OnboardingDraftStore extends ChangeNotifier with WidgetsBindingObserver {
  OnboardingDraftStore._();

  static final OnboardingDraftStore instance = OnboardingDraftStore._();

  static const _key = 'collaborator_onboarding_drafts';

  /// How often to retry on our own. Long, because the foreground and list-open
  /// triggers catch nearly everything and a tight loop on a dead connection is
  /// just battery.
  static const _retryInterval = Duration(minutes: 2);

  final Map<String, OnboardingDraft> _drafts = {};
  Timer? _timer;
  bool _syncing = false;
  bool _loaded = false;

  /// Drafts that still have to reach the server, newest first.
  List<OnboardingDraft> get pending => _drafts.values.where((d) => !d.submitted).toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  int get pendingCount => pending.length;

  /// Drafts that are complete and waiting only for a connection, as opposed to
  /// ones the collaborator has not finished filling in.
  int get queuedCount => pending.where((d) => d.isComplete).length;

  bool get isSyncing => _syncing;

  OnboardingDraft? forEnquiry(String enquiryId) => _drafts[enquiryId];

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);

    if (raw != null) {
      try {
        for (final entry in (jsonDecode(raw) as List)) {
          final draft = OnboardingDraft.fromJson(Map<String, dynamic>.from(entry));
          _drafts[draft.enquiryId] = draft;
        }
      } catch (_) {
        // A draft file we cannot read is worse than none: it would block every
        // future save. Start clean rather than wedge the queue.
        await prefs.remove(_key);
      }
    }

    WidgetsBinding.instance.addObserver(this);
    _timer ??= Timer.periodic(_retryInterval, (_) => sync());

    notifyListeners();
    unawaited(sync());
  }

  /// Start a draft for an assignment, or reopen the one already on the device.
  ///
  /// A correction is the interesting case: the device threw its draft away when
  /// the submission succeeded, so the salon on the server is the only copy of
  /// the visit. It is pulled back down and becomes the draft, and the
  /// collaborator edits rather than retypes. If that fetch fails they still get
  /// a usable form seeded from the enquiry.
  Future<OnboardingDraft> open(
    Map<String, dynamic> enquiry, {
    /// Pull the salon back down and edit that instead of starting fresh. Used
    /// for a correction and for editing a salon still queued for approval.
    String? prefillSalonId,
  }) async {
    await load();

    final id = enquiry['id'].toString();
    final existing = _drafts[id];

    if (existing != null && !existing.submitted) return existing;

    final draft = OnboardingDraft.fromEnquiry(enquiry);

    final salonId = prefillSalonId ?? enquiry['salon_id']?.toString();
    if (salonId != null) {
      final submitted = await CollaboratorApi.submittedSalon(salonId);
      if (submitted != null) draft.restoreFrom(submitted);
    }

    _drafts[id] = draft;
    await save(draft);

    return draft;
  }

  Future<void> save(OnboardingDraft draft) async {
    draft.updatedAt = DateTime.now();
    _drafts[draft.enquiryId] = draft;
    await _persist();
    notifyListeners();
  }

  Future<void> discard(String enquiryId) async {
    final draft = _drafts.remove(enquiryId);

    // The photos were copies made for this draft, so nothing else is holding
    // them.
    for (final path in draft?.photoPaths ?? const <String>[]) {
      unawaited(File(path).delete().catchError((_) => File(path)));
    }

    await _persist();
    notifyListeners();
  }

  /// Copy a picked photo somewhere it will survive. `image_picker` hands back a
  /// cache path the OS is free to delete, which for a draft that may sit for
  /// hours is not good enough.
  Future<String> keepPhoto(String pickedPath) async {
    final dir = await getApplicationDocumentsDirectory();
    final target = Directory('${dir.path}/onboarding_photos');
    if (!await target.exists()) await target.create(recursive: true);

    final name = '${DateTime.now().microsecondsSinceEpoch}${_extension(pickedPath)}';
    final saved = await File(pickedPath).copy('${target.path}/$name');

    return saved.path;
  }

  static String _extension(String path) {
    final dot = path.lastIndexOf('.');
    return dot == -1 ? '.jpg' : path.substring(dot);
  }

  /// Try to send everything that is finished and still unsent.
  ///
  /// Safe to call as often as anything likes: overlapping runs are collapsed,
  /// and the server treats a replayed submission as the one it already has.
  Future<void> sync() async {
    if (_syncing) return;

    final ready = pending.where((d) => d.isComplete).toList();
    if (ready.isEmpty) return;

    _syncing = true;
    notifyListeners();

    for (final draft in ready) {
      try {
        await CollaboratorApi.submit(draft);
        draft.submitted = true;
        draft.lastError = null;

        // It is on the server now; the local copy is just clutter, and its
        // photos have been uploaded.
        await discard(draft.enquiryId);
      } on OnboardingRejected catch (e) {
        // The server will say the same thing next time. Stop retrying this one
        // and put the reason where the collaborator will see it.
        draft.lastError = e.message;
        await save(draft);
      } catch (_) {
        // Almost certainly still offline. Leave it queued and say so.
        draft.lastError = null;
        break;
      }
    }

    await _persist();
    _syncing = false;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the foreground is the single best hint that the phone may
    // have found signal since we last looked.
    if (state == AppLifecycleState.resumed) unawaited(sync());
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_drafts.values.map((d) => d.toJson()).toList()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
