import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/onboarding_draft.dart';
import '../../services/api_service.dart';
import '../../services/collaborator_api.dart';
import '../../services/onboarding_draft_store.dart';
import '../../services/salon_location_api.dart';
import '../../theme/app_theme.dart';
import 'service_picker_sheet.dart';

/// Building a salon on behalf of an owner, on site.
///
/// Four steps, and the draft is written to disk behind every one of them. The
/// collaborator can lose signal, lose the app, or lose the afternoon and come
/// back to exactly what they had typed. Submitting is the only step that needs
/// a connection, and even that one degrades: a finished draft that cannot be
/// sent is queued and goes on its own once the phone finds a network.
class OnboardSalonScreen extends StatefulWidget {
  /// The assignment. A collaborator cannot onboard a salon nobody enquired
  /// about, so this is always present.
  final Map<String, dynamic> enquiry;

  /// Set when reopening a salon that has already been submitted — a correction
  /// SuperAdmin asked for, or a tidy-up while it waits in the queue. The form
  /// fills itself from the salon rather than from the enquiry.
  final String? editingSalonId;

  const OnboardSalonScreen({super.key, required this.enquiry, this.editingSalonId});

  @override
  State<OnboardSalonScreen> createState() => _OnboardSalonScreenState();
}

class _OnboardSalonScreenState extends State<OnboardSalonScreen> {
  final _store = OnboardingDraftStore.instance;
  final _pageController = PageController();

  OnboardingDraft? _draft;
  int _step = 0;
  bool _submitting = false;
  bool _locating = false;

  // Cities, loaded once and filtered by state like the owner's own sign-up.
  List<dynamic> _cities = [];
  List<String> _states = [];
  String? _selectedState;
  bool _loadingCities = true;

  final _ownerName = TextEditingController();
  final _ownerPhone = TextEditingController();
  final _ownerEmail = TextEditingController();
  final _salonName = TextEditingController();
  final _description = TextEditingController();
  final _salonPhone = TextEditingController();
  final _address = TextEditingController();
  final _pincode = TextEditingController();

  Timer? _autosave;

  static const _stepTitles = ['Salon & owner', 'Where it is', 'Opening hours', 'Services'];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final draft = await _store.open(widget.enquiry, prefillSalonId: widget.editingSalonId);

    _ownerName.text = draft.ownerName;
    _ownerPhone.text = draft.ownerPhone;
    _ownerEmail.text = draft.ownerEmail;
    _salonName.text = draft.salonName;
    _description.text = draft.description;
    _salonPhone.text = draft.salonPhone;
    _address.text = draft.address;
    _pincode.text = draft.pincode;

    if (mounted) setState(() => _draft = draft);

    final cities = await ApiService.fetchCities();
    if (!mounted) return;

    setState(() {
      _cities = cities;
      _states = cities
          .map((c) => c['state']?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      _selectedState = _stateOfSelectedCity(draft.cityId);
      _loadingCities = false;
    });

    // A draft restored from the server carries a city id but no name to show
    // for it — the names only arrive with this list.
    if (draft.cityId != null && draft.cityLabel.isEmpty) {
      final match = _cities.firstWhere(
        (c) => c['id'].toString() == draft.cityId,
        orElse: () => null,
      );
      if (match != null) {
        draft.cityLabel = match['name'].toString();
        await _store.save(draft);
      }
    }
  }

  String? _stateOfSelectedCity(String? cityId) {
    if (cityId == null) return null;
    for (final city in _cities) {
      if (city['id'].toString() == cityId) return city['state']?.toString().trim();
    }
    return null;
  }

  List<dynamic> get _citiesInState =>
      _cities.where((c) => c['state']?.toString().trim() == _selectedState).toList();

  /// Typing is cheap; writing to disk on every keystroke is not. A short debounce
  /// keeps the draft within a second of what is on screen.
  void _touch() {
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 600), _persist);
  }

  Future<void> _persist() async {
    final draft = _draft;
    if (draft == null) return;

    draft
      ..ownerName = _ownerName.text
      ..ownerPhone = _ownerPhone.text
      ..ownerEmail = _ownerEmail.text
      ..salonName = _salonName.text
      ..description = _description.text
      ..salonPhone = _salonPhone.text
      ..address = _address.text
      ..pincode = _pincode.text;

    await _store.save(draft);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _autosave?.cancel();
    // Whatever is on screen when they walk away is what they come back to.
    unawaited(_persist());
    _pageController.dispose();
    for (final c in [_ownerName, _ownerPhone, _ownerEmail, _salonName, _description, _salonPhone, _address, _pincode]) {
      c.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------------ steps

  Future<void> _goTo(int step) async {
    await _persist();
    if (!mounted) return;

    setState(() => _step = step);
    _pageController.animateToPage(step,
        duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
  }

  /// Going forward is gated; going back never is. A collaborator who wants to
  /// re-read what they typed two steps ago should not have to finish this one
  /// first.
  Future<void> _advance() async {
    await _persist();
    if (!mounted) return;

    if (_missingHere.isNotEmpty) {
      setState(() => _stepsAttempted.add(_step));
      _say(_missingHere.length == 1
          ? '${_missingHere.first} is required.'
          : 'Fill in the ${_missingHere.length} required fields marked in red.');
      return;
    }

    await _goTo(_step + 1);
  }

  /// Set once the collaborator has tried to leave a step with gaps on it, so
  /// the form stays quiet until they have actually had a go at filling it in.
  final Set<int> _stepsAttempted = {};

  List<String> get _missingHere => _draft!.missingOn(_step);

  bool _showErrorsOn(int step) => _stepsAttempted.contains(step);

  Future<void> _submit() async {
    await _persist();
    if (!mounted) return;

    final missing = _draft!.missingFields;

    if (missing.isNotEmpty) {
      // Land them on the earliest step that still has a gap, with its errors
      // showing, rather than on a snackbar that names a field they cannot see.
      final firstBadStep = [0, 1, 2].firstWhere((s) => _draft!.missingOn(s).isNotEmpty);

      setState(() => _stepsAttempted.addAll([0, 1, 2]));
      await _goTo(firstBadStep);

      if (mounted) {
        _say(missing.length == 1
            ? '${missing.first} is still required.'
            : '${missing.length} required fields are still empty.');
      }
      return;
    }

    final draft = _draft!;

    try {
      final response = await CollaboratorApi.submit(draft);
      await _store.discard(draft.enquiryId);

      if (!mounted) return;
      Navigator.pop(context, true);
      _say(response['message']?.toString() ?? 'Submitted for approval.');
    } on OnboardingRejected catch (e) {
      // The server read it and said no. Stay put so it can be fixed.
      draft.lastError = e.message;
      await _store.save(draft);
      if (mounted) _say(e.message);
    } catch (_) {
      // No signal. The draft is already saved and queued, so this is not a
      // failure from the collaborator's point of view — they are done.
      if (!mounted) return;
      Navigator.pop(context, true);
      _say('No connection. Saved — it will submit itself once you are back online.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _say(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    if (_draft == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      onPopInvokedWithResult: (_, _) => _persist(),
      child: Scaffold(
        backgroundColor: AppTheme.lightBg,
        appBar: AppBar(
          title: Text(_stepTitles[_step],
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(46),
            child: _buildStepBar(),
          ),
        ),
        body: Column(
          children: [
            if (_draft!.lastError != null) _buildRejectionBanner(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildProfileStep(),
                  _buildLocationStep(),
                  _buildHoursStep(),
                  _buildServicesStep(),
                ],
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepBar() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          children: [
            Row(
              children: List.generate(4, (i) {
                final done = i <= _step;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == 3 ? 0 : 6),
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: done ? AppTheme.accentColor : AppTheme.lightBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Step ${_step + 1} of 4',
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.lightTextBody)),
                const Row(
                  children: [
                    Icon(Icons.cloud_off_outlined, size: 13, color: AppTheme.lightTextBody),
                    SizedBox(width: 4),
                    Text('Saved on this device',
                        style: TextStyle(fontSize: 11.5, color: AppTheme.lightTextBody)),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

  /// SuperAdmin sent this one back. The reason belongs at the top of the form,
  /// not buried in a list the collaborator has already left.
  Widget _buildRejectionBanner() => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.lightDangerBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.lightDanger.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, size: 18, color: AppTheme.lightDanger),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_draft!.lastError!,
                  style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppTheme.lightDanger)),
            ),
          ],
        ),
      );

  Widget _buildFooter() {
    final isLast = _step == 3;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.lightBorder)),
      ),
      child: Row(
        children: [
          if (_step > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _submitting ? null : () => _goTo(_step - 1),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  side: const BorderSide(color: AppTheme.lightBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Back', style: TextStyle(color: AppTheme.lightTextBody)),
              ),
            ),
          if (_step > 0) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _submitting ? null : (isLast ? _submit : _advance),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                backgroundColor: AppTheme.accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? const SizedBox(
                      height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(isLast ? 'Submit for approval' : 'Continue',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- step 1

  Widget _buildProfileStep() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_showErrorsOn(0) && _missingHere.isNotEmpty) _buildMissingBanner(),
          _sectionTitle('The salon'),
          _label('Salon name', required: true),
          _field(_salonName, 'e.g. Hair Story', Icons.storefront_outlined,
              requiredAs: 'Salon name'),
          const SizedBox(height: 14),
          _label('Description', required: true),
          _field(_description, 'What makes this salon worth visiting', Icons.notes_outlined,
              lines: 3, requiredAs: 'Description'),
          const SizedBox(height: 6),
          const Text(
            'Customers see this on the salon page in place of a phone number, so it '
            'is the only thing selling the salon.',
            style: TextStyle(fontSize: 11.5, height: 1.35, color: AppTheme.lightTextBody),
          ),
          const SizedBox(height: 14),
          _label('Who it serves', required: true),
          Row(
            children: [
              for (final option in ['Unisex', 'Men Only', 'Women Only']) ...[
                _genderToggle(option),
                if (option != 'Women Only') const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _label('Salon phone', required: true),
          _field(_salonPhone, 'Reception line', Icons.call_outlined,
              keyboard: TextInputType.phone, requiredAs: 'Salon phone'),

          const SizedBox(height: 28),
          _sectionTitle('The owner'),
          const Text(
            'They sign in with this number and an OTP, so it has to be the one they carry.',
            style: TextStyle(fontSize: 12, height: 1.4, color: AppTheme.lightTextBody),
          ),
          const SizedBox(height: 14),
          _label('Owner name', required: true),
          _field(_ownerName, 'Full name', Icons.person_outline, requiredAs: 'Owner name'),
          const SizedBox(height: 14),
          _label('Owner phone', required: true),
          _field(_ownerPhone, '10-digit mobile', Icons.smartphone_outlined,
              keyboard: TextInputType.phone, requiredAs: 'Owner phone'),
          const SizedBox(height: 14),
          _label('Owner email', optional: true),
          _field(_ownerEmail, 'Leave blank if they do not have one', Icons.alternate_email,
              keyboard: TextInputType.emailAddress),
          const SizedBox(height: 20),
        ],
      );

  /// One summary at the top of a step once it has been attempted, so the
  /// collaborator can see the whole gap list without scrolling for red borders.
  Widget _buildMissingBanner() => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.lightDangerBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.lightDanger.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, size: 17, color: AppTheme.lightDanger),
                const SizedBox(width: 9),
                Text(
                  _missingHere.length == 1
                      ? '1 required field to fill in'
                      : '${_missingHere.length} required fields to fill in',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.lightDanger),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final field in _missingHere)
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 2),
                child: Text('• $field',
                    style: const TextStyle(fontSize: 12, color: AppTheme.lightDanger)),
              ),
          ],
        ),
      );

  // ------------------------------------------------------------- step 2

  Widget _buildLocationStep() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_showErrorsOn(1) && _missingHere.isNotEmpty) _buildMissingBanner(),
          _buildPinCard(),
          const SizedBox(height: 20),
          _label('Street address', required: true),
          _field(_address, 'Shop number, street, landmark', Icons.location_on_outlined,
              lines: 2, requiredAs: 'Street address'),
          const SizedBox(height: 14),
          _label('State', required: true),
          if (_loadingCities)
            const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
          else
            _dropdown<String>(
              value: _selectedState,
              hint: 'Select state',
              icon: Icons.map_outlined,
              items: _states.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedState = value;
                  _draft!.cityId = null;
                  _draft!.cityLabel = '';
                });
                _persist();
              },
            ),
          const SizedBox(height: 14),
          _label('City', required: true),
          if (!_loadingCities)
            _dropdown<String>(
              value: _draft!.cityId,
              hint: _selectedState == null ? 'Pick a state first' : 'Select city',
              icon: Icons.location_city_outlined,
              items: _citiesInState
                  .map((c) => DropdownMenuItem(
                      value: c['id'].toString(), child: Text(c['name'].toString())))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _draft!.cityId = value;
                  _draft!.cityLabel = _citiesInState
                      .firstWhere((c) => c['id'].toString() == value)['name']
                      .toString();
                });
                _persist();
              },
            ),
          const SizedBox(height: 14),
          _label('Pincode', required: true),
          _field(_pincode, '6 digits', Icons.pin_drop_outlined,
              keyboard: TextInputType.number, requiredAs: 'Pincode'),

          const SizedBox(height: 28),
          _sectionTitle('Photos', required: true),
          Text(
            _photoNote,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: _showErrorsOn(1) && _missingHere.contains('At least one photo')
                  ? AppTheme.lightDanger
                  : AppTheme.lightTextBody,
            ),
          ),
          const SizedBox(height: 12),
          _buildPhotoGrid(),
          const SizedBox(height: 20),
        ],
      );

  /// Photos already on the server need explaining, or a collaborator editing a
  /// salon sees an empty grid and assumes the gallery was lost.
  String get _photoNote {
    final draft = _draft!;

    if (draft.photoPaths.isNotEmpty) {
      return 'The cover is what customers see first. Tap another to promote it.';
    }

    if (draft.existingPhotoCount > 0) {
      final count = draft.existingPhotoCount;
      return '$count ${count == 1 ? 'photo is' : 'photos are'} already saved for this '
          'salon. Add photos here only to replace the whole set.';
    }

    return 'At least one photo is required — a salon with no picture gets skipped '
        'past in the customer app.';
  }

  /// Pinning matters more here than at owner sign-up: the collaborator is
  /// physically standing in the salon, which is the only moment the coordinates
  /// are free to get exactly right.
  Widget _buildPinCard() {
    final draft = _draft!;
    final pinned = draft.latitude != null && draft.longitude != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: pinned ? AppTheme.lightSuccessBg : AppTheme.accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: pinned
              ? AppTheme.lightSuccess.withValues(alpha: 0.4)
              : AppTheme.accentColor.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(pinned ? Icons.check_circle : Icons.place_outlined,
              size: 20, color: pinned ? AppTheme.lightSuccess : AppTheme.accentColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(pinned ? 'Salon pinned' : 'Pin the salon',
                        style:
                            const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                    if (!pinned)
                      const Text('  (optional)',
                          style:
                              TextStyle(fontSize: 11, color: AppTheme.lightTextLight)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  pinned
                      ? '${draft.latitude!.toStringAsFixed(5)}, ${draft.longitude!.toStringAsFixed(5)}'
                      : 'You are here now — customers browse nearest first, so this is '
                          'the best chance to get it right.',
                  style: const TextStyle(fontSize: 11.5, height: 1.35, color: AppTheme.lightTextBody),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _locating ? null : _capturePin,
                  icon: _locating
                      ? const SizedBox(
                          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location, size: 16),
                  label: Text(_locating ? 'Finding…' : (pinned ? 'Update pin' : 'Use this location'),
                      style: const TextStyle(fontSize: 12.5)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accentColor,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _capturePin() async {
    setState(() => _locating = true);
    final position = await SalonLocationApi.devicePosition();

    if (!mounted) return;
    setState(() {
      _locating = false;
      _draft!.latitude = position?.latitude;
      _draft!.longitude = position?.longitude;
    });

    await _persist();
    if (position == null) _say('Could not read the location. The salon can be pinned later.');
  }

  Widget _buildPhotoGrid() {
    final photos = _draft!.photoPaths;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < photos.length; i++) _buildPhotoTile(i, photos[i]),
        _buildAddPhotoTile(),
      ],
    );
  }

  Widget _buildPhotoTile(int index, String path) {
    final isCover = index == _draft!.coverIndex;

    return GestureDetector(
      onTap: () {
        setState(() => _draft!.coverIndex = index);
        _persist();
      },
      child: Stack(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCover ? AppTheme.accentColor : AppTheme.lightBorder,
                width: isCover ? 2 : 1,
              ),
              image: DecorationImage(image: FileImage(File(path)), fit: BoxFit.cover),
            ),
          ),
          if (isCover)
            Positioned(
              left: 4, bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Cover',
                    style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          Positioned(
            right: 0, top: 0,
            child: GestureDetector(
              onTap: () => _removePhoto(index),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 13, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddPhotoTile() => GestureDetector(
        onTap: _addPhoto,
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.lightBorder, style: BorderStyle.solid),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_a_photo_outlined, color: AppTheme.accentColor),
              SizedBox(height: 6),
              Text('Add', style: TextStyle(fontSize: 11, color: AppTheme.lightTextBody)),
            ],
          ),
        ),
      );

  Future<void> _addPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picked = await ImagePicker().pickImage(source: source, imageQuality: 80, maxWidth: 1600);
    if (picked == null) return;

    // Copied out of the picker's cache so the draft survives the OS reclaiming
    // temporary files while the collaborator is still out of signal.
    final kept = await _store.keepPhoto(picked.path);

    if (!mounted) return;
    setState(() => _draft!.photoPaths.add(kept));
    await _persist();
  }

  Future<void> _removePhoto(int index) async {
    final draft = _draft!;
    final removed = draft.photoPaths.removeAt(index);
    unawaited(File(removed).delete().catchError((_) => File(removed)));

    if (draft.coverIndex >= draft.photoPaths.length) {
      draft.coverIndex = draft.photoPaths.isEmpty ? 0 : draft.photoPaths.length - 1;
    }

    setState(() {});
    await _persist();
  }

  // ------------------------------------------------------------- step 3

  Widget _buildHoursStep() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_showErrorsOn(2) && _missingHere.isNotEmpty) _buildMissingBanner(),
          const Text(
            'When is the salon open? Customers can only book inside these hours, so '
            'at least one day has to be open.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: AppTheme.lightTextBody),
          ),
          const SizedBox(height: 16),
          for (final day in _draft!.workingHours) _buildDayRow(day),
          const SizedBox(height: 20),
        ],
      );

  Widget _buildDayRow(DraftWorkingDay day) {
    final invalid = !day.isValid;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: invalid ? AppTheme.lightDanger : AppTheme.lightBorder),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(day.name,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: day.isClosed
                ? const Text('Closed',
                    style: TextStyle(fontSize: 13, color: AppTheme.lightTextBody))
                : Row(
                    children: [
                      _timeChip(day, isOpen: true),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('–', style: TextStyle(color: AppTheme.lightTextBody)),
                      ),
                      _timeChip(day, isOpen: false),
                    ],
                  ),
          ),
          Switch(
            value: !day.isClosed,
            activeThumbColor: AppTheme.accentColor,
            onChanged: (open) {
              setState(() => day.isClosed = !open);
              _persist();
            },
          ),
        ],
      ),
    );
  }

  Widget _timeChip(DraftWorkingDay day, {required bool isOpen}) {
    final value = isOpen ? day.openTime : day.closeTime;

    return GestureDetector(
      onTap: () async {
        final parts = value.split(':');
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(
              hour: int.tryParse(parts.first) ?? 10, minute: int.tryParse(parts.last) ?? 0),
        );
        if (picked == null) return;

        final formatted =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';

        setState(() {
          if (isOpen) {
            day.openTime = formatted;
          } else {
            day.closeTime = formatted;
          }
        });
        await _persist();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.lightAccentSoft,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(value,
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.accentColor)),
      ),
    );
  }

  // ------------------------------------------------------------- step 4

  Widget _buildServicesStep() {
    final services = _draft!.services;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.lightInfoBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: AppTheme.lightInfo),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Services are optional — the only optional step. Skip them and the '
                  'owner can price their own menu once they sign in.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: AppTheme.lightInfo),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        for (var i = 0; i < services.length; i++) _buildServiceRow(i, services[i]),

        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: _addService,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add a service'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.accentColor,
            padding: const EdgeInsets.symmetric(vertical: 13),
            side: const BorderSide(color: AppTheme.accentColor),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),

        const SizedBox(height: 28),
        _buildReviewCard(),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildServiceRow(int index, DraftService service) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.lightBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(service.name,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('${service.categoryName} · ${service.durationMinutes} min',
                      style: const TextStyle(fontSize: 11.5, color: AppTheme.lightTextBody)),
                ],
              ),
            ),
            Text('₹${service.price.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: AppTheme.lightTextBody),
              onPressed: () {
                setState(() => _draft!.services.removeAt(index));
                _persist();
              },
            ),
          ],
        ),
      );

  Future<void> _addService() async {
    final service = await showModalBottomSheet<DraftService>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ServicePickerSheet(),
    );

    if (service == null) return;

    setState(() => _draft!.services.add(service));
    await _persist();
  }

  /// The last thing before submitting: what is about to be sent, and what is
  /// still missing if anything is.
  Widget _buildReviewCard() {
    final draft = _draft!;
    final missing = draft.missingFields;
    final openDays = draft.workingHours.where((d) => !d.isClosed).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(missing.isEmpty ? 'Ready to send' : 'Not ready yet',
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _reviewRow(Icons.storefront_outlined,
              draft.salonName.isEmpty ? 'No salon name' : draft.salonName),
          _reviewRow(Icons.person_outline,
              '${draft.ownerName.isEmpty ? 'Owner' : draft.ownerName} · ${draft.ownerPhone}'),
          _reviewRow(Icons.location_on_outlined,
              [draft.address, draft.cityLabel].where((s) => s.isNotEmpty).join(', ')),
          _reviewRow(Icons.schedule, '$openDays open ${openDays == 1 ? 'day' : 'days'} a week'),
          _reviewRow(Icons.spa_outlined,
              '${draft.services.length} ${draft.services.length == 1 ? 'service' : 'services'}'),
          _reviewRow(Icons.photo_library_outlined,
              '${draft.photoPaths.length} ${draft.photoPaths.length == 1 ? 'photo' : 'photos'}'),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 16, color: AppTheme.lightWarning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Still required: ${missing.join(', ')}.',
                    style:
                        const TextStyle(fontSize: 12, height: 1.4, color: AppTheme.lightWarning),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _reviewRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: AppTheme.lightTextBody),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text.isEmpty ? '—' : text,
                  style: const TextStyle(fontSize: 12.5, color: AppTheme.lightTextBody)),
            ),
          ],
        ),
      );

  // ------------------------------------------------------------- widgets

  Widget _sectionTitle(String text, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Text(text,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.lightTextHeading)),
            if (required)
              const Text(' *',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.lightDanger)),
          ],
        ),
      );

  /// A required field carries a red asterisk; an optional one says so in words.
  /// Nothing is left for the collaborator to guess at.
  Widget _label(String text, {bool required = false, bool optional = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            if (required)
              const Text(' *',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.lightDanger)),
            if (optional)
              const Text('  (optional)',
                  style: TextStyle(fontSize: 11, color: AppTheme.lightTextLight)),
          ],
        ),
      );

  Widget _field(
    TextEditingController controller,
    String hint,
    IconData icon, {
    TextInputType? keyboard,
    int lines = 1,

    /// Named so the field can go red once this step has been attempted and this
    /// particular value is still one of the gaps.
    String? requiredAs,
  }) {
    final invalid = requiredAs != null &&
        _showErrorsOn(_step) &&
        _missingHere.any((m) => m.startsWith(requiredAs));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          keyboardType: keyboard,
          maxLines: lines,
          onChanged: (_) => _touch(),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppTheme.lightTextLight, fontSize: 13.5),
            prefixIcon: Icon(icon,
                size: 19,
                color: invalid ? AppTheme.lightDanger : AppTheme.lightTextLight),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            border: _border(invalid ? AppTheme.lightDanger : AppTheme.lightBorder),
            enabledBorder: _border(invalid ? AppTheme.lightDanger : AppTheme.lightBorder),
            focusedBorder: _border(invalid ? AppTheme.lightDanger : AppTheme.accentColor),
          ),
        ),
        if (invalid)
          Padding(
            padding: const EdgeInsets.only(top: 5, left: 2),
            child: Text(
              _missingHere.firstWhere((m) => m.startsWith(requiredAs)),
              style: const TextStyle(fontSize: 11.5, color: AppTheme.lightDanger),
            ),
          ),
      ],
    );
  }

  Widget _dropdown<T>({
    required T? value,
    required String hint,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) =>
      DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        hint: Text(hint, style: const TextStyle(color: AppTheme.lightTextLight, fontSize: 13.5)),
        items: items,
        onChanged: items.isEmpty ? null : onChanged,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, size: 19, color: AppTheme.lightTextLight),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: _border(AppTheme.lightBorder),
          enabledBorder: _border(AppTheme.lightBorder),
          focusedBorder: _border(AppTheme.accentColor),
        ),
      );

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color),
      );

  Widget _genderToggle(String label) {
    final selected = _draft!.genderFocus == label;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _draft!.genderFocus = label);
          _persist();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppTheme.lightAccentSoft : Colors.white,
            border: Border.all(color: selected ? AppTheme.accentColor : AppTheme.lightBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? AppTheme.accentColor : AppTheme.lightTextBody,
            ),
          ),
        ),
      ),
    );
  }
}
