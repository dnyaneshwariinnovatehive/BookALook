import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/onboarding_draft.dart';
import '../../models/subscription_plan.dart';
import '../../services/api_service.dart';
import '../../services/collaborator_api.dart';
import '../../services/onboarding_draft_store.dart';
import '../../services/salon_location_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sub_area_dropdown.dart';
import '../../widgets/bank_details_fields.dart';
import 'service_picker_sheet.dart';

/// Building a salon on behalf of an owner, on site.
///
/// Four steps, and the draft is written to disk behind every one of them. The
/// collaborator can lose signal, lose the app, or lose the afternoon and come
/// back to exactly what they had typed. Submitting is the only step that needs
/// a connection, and even that one degrades: a finished draft that cannot be
/// sent is queued and goes on its own once the phone finds a network.
class OnboardSalonScreen extends StatefulWidget {
  /// The assignment. When onboarding an enquiry, this holds the enquiry details.
  /// When onboarding a new salon directly, this is null.
  final Map<String, dynamic>? enquiry;

  /// Set when reopening a salon that has already been submitted — a correction
  /// SuperAdmin asked for, or a tidy-up while it waits in the queue. The form
  /// fills itself from the salon rather than from the enquiry.
  final String? editingSalonId;

  const OnboardSalonScreen({super.key, this.enquiry, this.editingSalonId});

  @override
  State<OnboardSalonScreen> createState() => OnboardSalonScreenState();
}

class OnboardSalonScreenState extends State<OnboardSalonScreen> {
  final _store = OnboardingDraftStore.instance;
  final _pageController = PageController();

  OnboardingDraft? _draft;
  OnboardingDraft? get draft => _draft;
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
  final _bank = BankDetailsControllers();
  final _salonName = TextEditingController();
  final _description = TextEditingController();
  final _salonPhone = TextEditingController();
  final _address = TextEditingController();
  final _pincode = TextEditingController();
  final _commissionController = TextEditingController();
  List<dynamic> _subscriptionPlans = [];
  List<dynamic>? _masterCatalogCategories;

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
    if (draft.requestedCommissionPercentage != null) {
      _commissionController.text = draft.requestedCommissionPercentage.toString();
    }
    _fillBank(draft);

    if (mounted) setState(() => _draft = draft);

    final results = await Future.wait([
      ApiService.fetchCities(),
      ApiService.getSubscriptionPlans(),
      CollaboratorApi.masterCatalog().catchError((_) => <dynamic>[]),
    ]);

    if (!mounted) return;

    final cities = results[0];
    final plans = results[1];
    final masterCatalog = results.length > 2 ? results[2] : null;

    setState(() {
      _cities = cities;
      _subscriptionPlans = plans;
      _masterCatalogCategories = masterCatalog;
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

  @visibleForTesting
  void seedForTest({
    required OnboardingDraft draft,
    List<dynamic>? subscriptionPlans,
  }) {
    _draft = draft;
    _ownerName.text = draft.ownerName;
    _ownerPhone.text = draft.ownerPhone;
    _ownerEmail.text = draft.ownerEmail;
    _salonName.text = draft.salonName;
    _description.text = draft.description;
    _salonPhone.text = draft.salonPhone;
    _address.text = draft.address;
    _pincode.text = draft.pincode;
    if (draft.requestedCommissionPercentage != null) {
      _commissionController.text = draft.requestedCommissionPercentage.toString();
    }
    if (subscriptionPlans != null) {
      _subscriptionPlans = subscriptionPlans;
    }
    setState(() {});
  }

  void _fillBank(OnboardingDraft draft) {
    _bank.fillFromMap({
      'bank_account_holder_name': draft.bankHolder,
      'bank_name': draft.bankName,
      'bank_account_number': draft.bankAccount,
      'bank_ifsc': draft.bankIfsc,
      'bank_upi_id': draft.bankUpi,
    });
    _bank.hasSavedAccount = draft.hasSavedBankAccount;
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
      ..pincode = _pincode.text
      ..bankHolder = _bank.holder.text
      ..bankName = _bank.bankName.text
      ..bankAccount = _bank.account.text
      ..bankIfsc = _bank.ifsc.text
      ..bankUpi = _bank.upi.text;

    final parsedCommission = double.tryParse(_commissionController.text.trim());
    draft.requestedCommissionPercentage = parsedCommission;

    await _store.save(draft);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _autosave?.cancel();
    // Whatever is on screen when they walk away is what they come back to.
    unawaited(_persist().whenComplete(_bank.dispose));
    _pageController.dispose();
    for (final c in [
      _ownerName,
      _ownerPhone,
      _ownerEmail,
      _salonName,
      _description,
      _salonPhone,
      _address,
      _pincode,
      _commissionController
    ]) {
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
    // The last step's button is the one thing a collaborator can double-tap, and
    // two submissions of the same draft used to reach the server at once. It had
    // to be the server's problem to absorb, and the unique index on a salon's
    // working hours did not absorb it — it rejected the second one outright.
    // Better not to send it.
    if (_submitting) return;
    setState(() => _submitting = true);

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
        setState(() => _submitting = false);
        _say(missing.length == 1
            ? '${missing.first} is still required.'
            : '${missing.length} required fields are still empty.');
      }
      return;
    }

    final draft = _draft!;

    try {
      final response = await CollaboratorApi.submit(draft);
      draft.submitted = true;
      draft.queuedForSubmission = false;
      if (response['data']?['id'] != null) {
        draft.editingSalonId = response['data']['id'].toString();
      }
      await _store.discard(draft.enquiryId);

      if (!mounted) return;
      Navigator.pop(context, true);
      _say(response['message']?.toString() ?? 'Submitted for approval.');
    } on OnboardingRejected catch (e) {
      // The server read it and said no. Stay put so it can be fixed.
      draft.lastError = e.message;
      draft.queuedForSubmission = false;
      await _store.save(draft);
      if (mounted) _say(e.message);
    } catch (_) {
      // No signal. The draft is now saved and queued for background sync once online.
      draft.queuedForSubmission = true;
      await _store.save(draft);

      if (!mounted) return;
      Navigator.pop(context, true);
      _say('No connection. Saved — it will submit itself once you are back online.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _say(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(duration: const Duration(milliseconds: 2500), content: Text(message)));
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
          _label('Reception number', optional: true),
          _field(_salonPhone, 'Reception line (optional)', Icons.call_outlined,
              keyboard: TextInputType.phone),

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

          const SizedBox(height: 28),
          _sectionTitle('Bank details'),
          Text(
            _draft!.savedBankSummary.isNotEmpty
                ? 'Optional. On file: ${_draft!.savedBankSummary}. Leave the account number empty to keep it.'
                : 'Optional. Where BookALook sends the salon\'s settlements. The owner can add these later in the app.',
            key: const ValueKey('onboard_bank_note'),
            style: const TextStyle(fontSize: 12, height: 1.4, color: AppTheme.lightTextBody),
          ),
          const SizedBox(height: 14),
          BankDetailsFields(controllers: _bank, onChanged: _touch),

          const SizedBox(height: 28),
          _sectionTitle('Commercial preferences'),
          const Text(
            'Select the preferred commercial model. SuperAdmin sets the authoritative commission rate during review.',
            style: TextStyle(fontSize: 12, height: 1.4, color: AppTheme.lightTextBody),
          ),
          const SizedBox(height: 14),
          _label('Commercial model', required: true),
          Row(
            children: [
              Expanded(child: _commercialModelToggle('subscription', 'Subscription Plan')),
              const SizedBox(width: 8),
              Expanded(child: _commercialModelToggle('commission', 'Commission Model')),
            ],
          ),
          if ((_draft!.preferredCommercialModel) == 'subscription') ...[
            const SizedBox(height: 14),
            _label('Preferred subscription plan', optional: true),
            _buildSubscriptionPlanSelector(),
            const SizedBox(height: 6),
            const Text(
              'Registration preference only. The salon confirms and purchases their actual plan after approval.',
              style: TextStyle(fontSize: 11.5, height: 1.35, color: AppTheme.lightTextBody),
            ),
          ],
          if (_draft!.preferredCommercialModel == 'commission') ...[
            const SizedBox(height: 14),
            _label('Requested commission rate (%)', required: true),
            _field(_commissionController, 'e.g. 15.0', Icons.percent,
                keyboard: const TextInputType.numberWithOptions(decimal: true),
                requiredAs: 'Requested commission rate (0-100%)'),
            const SizedBox(height: 6),
            const Text(
              'Requested percentage. SuperAdmin reviews and finalizes the approved commission rate.',
              style: TextStyle(fontSize: 11.5, height: 1.35, color: AppTheme.lightTextBody),
            ),
          ],
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
                  // The old area belonged to the old city.
                  _draft!.subAreaId = null;
                  _draft!.subAreaLabel = '';
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
                  _draft!.subAreaId = null;
                  _draft!.subAreaLabel = '';
                });
                _persist();
              },
            ),
          const SizedBox(height: 14),
          _label('Area', required: true),
          SubAreaDropdown(
            cityId: _draft!.cityId,
            value: _draft!.subAreaId,
            showError: _showErrorsOn(1) && _missingHere.contains('Area'),
            onChanged: (value) {
              setState(() => _draft!.subAreaId = value);
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

  ImageProvider _photoImageProvider(String path) {
    if (kIsWeb || path.startsWith('http://') || path.startsWith('https://')) {
      return NetworkImage(path);
    }
    return FileImage(File(path));
  }

  Widget _buildPhotoGrid() {
    final photos = _draft!.photoPaths;
    if (photos.isEmpty) {
      return Row(
        children: [
          _buildAddPhotoTile(),
        ],
      );
    }

    final safeCoverIndex = _draft!.coverIndex.clamp(0, photos.length - 1);
    final coverPath = photos[safeCoverIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Featured Cover Photo Preview Card
        GestureDetector(
          onTap: () => _showCoverPhotoSelectorSheet(initialIndex: safeCoverIndex),
          child: Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.black12,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
              image: DecorationImage(
                image: _photoImageProvider(coverPath),
                fit: BoxFit.cover,
              ),
            ),
            child: Stack(
              children: [
                // Subtle gradient for contrast
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.4),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.6),
                        ],
                        stops: const [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                ),
                // Top Badge: Cover Photo
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Main Cover Photo',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Top Right Action: Change Cover
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tune, color: Colors.white, size: 13),
                        SizedBox(width: 4),
                        Text(
                          'Change Cover',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Bottom Caption
                Positioned(
                  bottom: 12,
                  left: 12,
                  right: 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Photo ${safeCoverIndex + 1} of ${photos.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Text(
                        'Tap to switch cover',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Section header for all photos
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'All Photos (${photos.length})',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppTheme.lightTextHeading,
              ),
            ),
            const Text(
              'Tap any photo to set as cover',
              style: TextStyle(fontSize: 11, color: AppTheme.lightTextLight),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Thumbnails Wrap
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < photos.length; i++) _buildPhotoTile(i, photos[i]),
            _buildAddPhotoTile(),
          ],
        ),
      ],
    );
  }

  Widget _buildPhotoTile(int index, String path) {
    final isCover = index == _draft!.coverIndex;

    return GestureDetector(
      onTap: () => _showCoverPhotoSelectorSheet(initialIndex: index),
      child: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCover ? AppTheme.accentColor : AppTheme.lightBorder,
                width: isCover ? 2.5 : 1,
              ),
              boxShadow: isCover
                  ? [
                      BoxShadow(
                        color: AppTheme.accentColor.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
              image: DecorationImage(
                image: _photoImageProvider(path),
                fit: BoxFit.cover,
              ),
            ),
          ),
          if (isCover)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star, size: 10, color: Colors.white),
                    SizedBox(width: 2),
                    Text('Cover',
                        style: TextStyle(
                            fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          Positioned(
            right: 2,
            top: 2,
            child: GestureDetector(
              onTap: () => _removePhoto(index),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 12, color: Colors.white),
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
              Text('Add Photos', style: TextStyle(fontSize: 11, color: AppTheme.lightTextBody)),
            ],
          ),
        ),
      );

  Future<void> _addPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Upload Salon Photos',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppTheme.accentColor),
              title: const Text('Take a photo with camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppTheme.accentColor),
              title: const Text('Choose from gallery (multiple supported)'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;

    final addedPaths = <String>[];

    if (source == ImageSource.gallery) {
      final pickedFiles = await ImagePicker().pickMultiImage(
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (pickedFiles.isEmpty) return;
      for (final xfile in pickedFiles) {
        final kept = await _store.keepPhoto(xfile.path);
        addedPaths.add(kept);
      }
    } else {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (picked == null) return;
      final kept = await _store.keepPhoto(picked.path);
      addedPaths.add(kept);
    }

    if (!mounted || addedPaths.isEmpty) return;

    setState(() {
      _draft!.photoPaths.addAll(addedPaths);
      if (_draft!.coverIndex >= _draft!.photoPaths.length) {
        _draft!.coverIndex = 0;
      }
    });

    await _persist();

    // Right when photos are uploaded, ask which photo should be cover photo and show preview!
    if (mounted && _draft!.photoPaths.isNotEmpty) {
      await _showCoverPhotoSelectorSheet();
    }
  }

  /// Opens an interactive preview sheet asking the collaborator to choose
  /// which uploaded photo should be the cover photo.
  Future<void> _showCoverPhotoSelectorSheet({int? initialIndex}) async {
    final draft = _draft;
    if (draft == null || draft.photoPaths.isEmpty) return;

    int candidateIndex = (initialIndex ?? draft.coverIndex).clamp(0, draft.photoPaths.length - 1);

    await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final selectedPath = draft.photoPaths[candidateIndex];

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.accentColor.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.star_rounded, color: AppTheme.accentColor, size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Select Cover Photo',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.lightTextHeading,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Choose which photo will be the main cover for customers',
                                style: TextStyle(fontSize: 12, color: AppTheme.lightTextBody),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Large Live Preview of Selected Cover Photo
                    Text(
                      'COVER PHOTO PREVIEW',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.black12,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        image: DecorationImage(
                          image: _photoImageProvider(selectedPath),
                          fit: BoxFit.cover,
                        ),
                      ),
                      child: Stack(
                        children: [
                          // Gradient overlay
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.4),
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.6),
                                  ],
                                  stops: const [0.0, 0.45, 1.0],
                                ),
                              ),
                            ),
                          ),
                          // Badge: Main Storefront Cover
                          Positioned(
                            top: 12,
                            left: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppTheme.accentColor,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.star, color: Colors.white, size: 14),
                                  SizedBox(width: 4),
                                  Text(
                                    'Main Cover Photo',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Indicator: Photo X of Y
                          Positioned(
                            bottom: 12,
                            left: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Photo ${candidateIndex + 1} of ${draft.photoPaths.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Thumbnails label
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Tap a photo to set as cover:',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        Text(
                          '${draft.photoPaths.length} uploaded',
                          style: const TextStyle(fontSize: 12, color: AppTheme.lightTextLight),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Thumbnails list
                    SizedBox(
                      height: 84,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: draft.photoPaths.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, idx) {
                          final isSelected = idx == candidateIndex;
                          final thumbPath = draft.photoPaths[idx];

                          return GestureDetector(
                            onTap: () {
                              setModalState(() {
                                candidateIndex = idx;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? AppTheme.accentColor : Colors.grey.shade300,
                                  width: isSelected ? 3 : 1,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: AppTheme.accentColor.withValues(alpha: 0.3),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                                image: DecorationImage(
                                  image: _photoImageProvider(thumbPath),
                                  fit: BoxFit.cover,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  if (isSelected)
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: AppTheme.accentColor,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.check, size: 14, color: Colors.white),
                                      ),
                                    ),
                                  if (isSelected)
                                    Positioned(
                                      bottom: 4,
                                      left: 4,
                                      right: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.accentColor.withValues(alpha: 0.9),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'Cover',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 22),

                    // Confirm Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext, candidateIndex);
                        },
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: Text(
                          'Set Photo #${candidateIndex + 1} as Cover',
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (candidateIndex != draft.coverIndex) {
      setState(() {
        draft.coverIndex = candidateIndex;
      });
      await _persist();
      _say('Cover photo set to Photo #${candidateIndex + 1}');
    }
  }

  Future<void> _removePhoto(int index) async {
    final draft = _draft!;
    final removed = draft.photoPaths.removeAt(index);
    if (!kIsWeb) {
      unawaited(File(removed).delete().catchError((_) => File(removed)));
    }

    if (draft.photoPaths.isEmpty) {
      draft.coverIndex = 0;
    } else if (draft.coverIndex >= draft.photoPaths.length) {
      draft.coverIndex = draft.photoPaths.length - 1;
    } else if (draft.coverIndex > index) {
      draft.coverIndex--;
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
    final existingTemplateIds = <String>{};
    final existingCustomIdentities = <String>{};

    for (final s in _draft!.services) {
      if (s.templateId != null && s.templateId!.isNotEmpty) {
        existingTemplateIds.add(s.templateId!);
      } else {
        existingCustomIdentities.add(ServicePickerSheet.normalizeCustomIdentity(s.categoryName, s.name));
      }
    }

    final service = await showModalBottomSheet<DraftService>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ServicePickerSheet(
        initialCategories: _masterCatalogCategories,
        existingTemplateIds: existingTemplateIds,
        existingCustomIdentities: existingCustomIdentities,
      ),
    );

    if (service == null) return;

    // Defensive duplicate guard: reject if duplicate slips through
    if (_isDuplicateService(service)) {
      _say('This service has already been added to the draft.');
      return;
    }

    setState(() => _draft!.services.add(service));
    await _persist();
  }

  bool _isDuplicateService(DraftService candidate) {
    for (final s in _draft!.services) {
      if (candidate.templateId != null && candidate.templateId!.isNotEmpty) {
        if (s.templateId == candidate.templateId) return true;
      } else {
        if (s.templateId == null || s.templateId!.isEmpty) {
          final id1 = ServicePickerSheet.normalizeCustomIdentity(s.categoryName, s.name);
          final id2 = ServicePickerSheet.normalizeCustomIdentity(candidate.categoryName, candidate.name);
          if (id1 == id2) return true;
        }
      }
    }
    return false;
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
              '${draft.photoPaths.length} ${draft.photoPaths.length == 1 ? 'photo' : 'photos'} (Cover set)'),
          _reviewRow(Icons.account_balance_wallet_outlined,
              draft.preferredCommercialModel == 'commission'
                  ? 'Commercial: Commission Model (${draft.requestedCommissionPercentage ?? 0}%)'
                  : 'Commercial: Subscription Plan'),
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

  String _formatPlanDetails(Map<String, dynamic> p) {
    final name = (p['name'] ?? 'Plan').toString();
    final rawPrice = p['price'];
    final numPrice = rawPrice != null ? double.tryParse(rawPrice.toString()) : null;
    final priceStr = numPrice != null
        ? '₹${numPrice.toStringAsFixed(numPrice.truncateToDouble() == numPrice ? 0 : 2)}'
        : (rawPrice != null ? '₹$rawPrice' : '');

    final days = p['validity_days'] ?? p['duration_days'] ?? 30;

    final details = <String>[];
    if (priceStr.isNotEmpty) details.add(priceStr);
    details.add('$days days');

    final advanced = p['has_advanced_insights'] == true ||
        p['has_advanced_insights'] == 1 ||
        p['has_advanced_insights'] == '1';
    details.add(advanced ? 'Growth insights' : 'Basic insights');

    return '$name (${details.join(' · ')})';
  }

  Widget _dropdown<T>({
    required T? value,
    required String hint,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    final effectiveValue = items.any((i) => i.value == value) ? value : null;
    return DropdownButtonFormField<T>(
      value: effectiveValue,
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
  }

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

  Widget _commercialModelToggle(String value, String label) {
    final selected = _draft!.preferredCommercialModel == value;

    return GestureDetector(
      onTap: () {
        setState(() {
          _draft!.preferredCommercialModel = value;
          if (value == 'commission') {
            _draft!.preferredPlanId = null;
          } else if (value == 'subscription') {
            // "Choose after approval" is selected by default
            _draft!.preferredPlanId ??= null;
          }
        });
        _persist();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.lightAccentSoft : Colors.white,
          border: Border.all(
            color: selected ? AppTheme.accentColor : AppTheme.lightBorder,
            width: selected ? 1.5 : 1.0,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 16,
              color: selected ? AppTheme.accentColor : AppTheme.lightTextLight,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? AppTheme.accentColor : AppTheme.lightTextBody,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionPlanSelector() {
    String displayText = 'Not sure yet (Choose after approval)';
    if (_draft!.preferredPlanId != null) {
      final selectedMap = _subscriptionPlans.cast<dynamic>().firstWhere(
        (p) {
          final map = p is Map ? p : (p is SubscriptionPlan ? p.rawJson : <String, dynamic>{});
          return map['id']?.toString() == _draft!.preferredPlanId;
        },
        orElse: () => null,
      );
      if (selectedMap != null) {
        final map = selectedMap is Map
            ? Map<String, dynamic>.from(selectedMap)
            : (selectedMap as SubscriptionPlan).rawJson;
        displayText = _formatPlanDetails(map);
      }
    }

    return InkWell(
      onTap: _openSubscriptionPlanSheet,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.lightBorder),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.card_membership_outlined,
              size: 20,
              color: AppTheme.lightTextLight,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.lightTextHeading,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 22,
              color: AppTheme.lightTextLight,
            ),
          ],
        ),
      ),
    );
  }

  void _openSubscriptionPlanSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetContext) {
        return _SubscriptionPlanBottomSheet(
          selectedPlanId: _draft!.preferredPlanId,
          plans: _subscriptionPlans,
          formatPlanDetails: _formatPlanDetails,
          onSelect: (selectedId) {
            setState(() => _draft!.preferredPlanId = selectedId);
            _persist();
            Navigator.pop(sheetContext);
          },
        );
      },
    );
  }
}

class _SubscriptionPlanBottomSheet extends StatelessWidget {
  final String? selectedPlanId;
  final List<dynamic> plans;
  final String Function(Map<String, dynamic>) formatPlanDetails;
  final ValueChanged<String?> onSelect;

  const _SubscriptionPlanBottomSheet({
    required this.selectedPlanId,
    required this.plans,
    required this.formatPlanDetails,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: screenHeight * 0.70,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 44,
                height: 4.5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),

            // Header row with Title and Dismiss (Close) button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Choose Subscription Plan',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : AppTheme.lightTextHeading,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Select a plan to express preference or decide after approval',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : AppTheme.lightTextBody,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 22),
                    tooltip: 'Dismiss',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Scrollable list of plans
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  // Preferred default option: "Choose after approval"
                  _buildChooseAfterApprovalCard(context, isDark),
                  const SizedBox(height: 18),

                  if (plans.isNotEmpty) ...[
                    Row(
                      children: [
                        Text(
                          'AVAILABLE PLANS (${plans.length})',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: isDark ? Colors.white54 : AppTheme.lightTextLight,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Responsive grid of cards
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 550;
                        final cardWidth = isWide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (var p in plans)
                              SizedBox(
                                width: cardWidth,
                                child: _buildPlanCard(context, p, isDark),
                              ),
                          ],
                        );
                      },
                    ),
                  ] else ...[
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'No subscription plans available right now.',
                          style: TextStyle(
                            color: isDark ? Colors.white54 : AppTheme.lightTextLight,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChooseAfterApprovalCard(BuildContext context, bool isDark) {
    final isSelected = selectedPlanId == null;

    return InkWell(
      onTap: () => onSelect(null),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppTheme.accentColor.withValues(alpha: 0.12) : AppTheme.lightAccentSoft)
              : (isDark ? const Color(0xFF252538) : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.accentColor : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.accentColor.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppTheme.accentColor : AppTheme.lightTextLight,
                  width: 2.0,
                ),
              ),
              alignment: Alignment.center,
              child: isSelected
                  ? Container(
                      width: 11,
                      height: 11,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.accentColor,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Not sure yet (Choose after approval)',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? AppTheme.accentColor : (isDark ? Colors.white : AppTheme.lightTextHeading),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'RECOMMENDED',
                          style: GoogleFonts.outfit(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: AppTheme.accentColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'No upfront commitment. The salon can compare plans and activate their subscription once approved.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: isDark ? Colors.white70 : AppTheme.lightTextBody,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(BuildContext context, dynamic p, bool isDark) {
    final map = p is Map ? Map<String, dynamic>.from(p) : (p is SubscriptionPlan ? p.rawJson : <String, dynamic>{});
    final planId = map['id']?.toString() ?? '';
    final isSelected = selectedPlanId == planId;
    final name = (map['name'] ?? 'Plan').toString();

    final rawPrice = map['price'];
    final numPrice = rawPrice != null ? double.tryParse(rawPrice.toString()) : null;
    final priceStr = numPrice != null
        ? '₹${numPrice.toStringAsFixed(numPrice.truncateToDouble() == numPrice ? 0 : 2)}'
        : (rawPrice != null ? '₹$rawPrice' : '₹0');

    final days = map['validity_days'] ?? map['duration_days'] ?? 30;

    final campaigns = map['whatsapp_campaign_limit'];
    final parsedCampaigns = campaigns != null ? int.tryParse(campaigns.toString()) : null;

    final hasPriority = map['has_priority_visibility'] == true ||
        map['has_priority_visibility'] == 1 ||
        map['has_priority_visibility'] == '1';

    final formattedDetails = formatPlanDetails(map);

    return InkWell(
      onTap: () => onSelect(planId),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppTheme.accentColor.withValues(alpha: 0.12) : AppTheme.lightAccentSoft)
              : (isDark ? const Color(0xFF252538) : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.accentColor : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.accentColor.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Radio, Name, Badges
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? AppTheme.accentColor : AppTheme.lightTextLight,
                      width: 2.0,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: isSelected
                      ? Container(
                          width: 11,
                          height: 11,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.accentColor,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$name Plan',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? AppTheme.accentColor : (isDark ? Colors.white : AppTheme.lightTextHeading),
                    ),
                  ),
                ),
                if (hasPriority)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded, size: 13, color: Colors.amber),
                        const SizedBox(width: 3),
                        Text(
                          'Priority',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber[800],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Price & Duration
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  priceStr,
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: isSelected ? AppTheme.accentColor : (isDark ? Colors.white : AppTheme.lightTextHeading),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  ' / $days days',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white70 : AppTheme.lightTextBody,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Formatted details summary
            Text(
              formattedDetails,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : AppTheme.lightTextBody,
                fontWeight: FontWeight.w500,
              ),
            ),

            if (parsedCampaigns != null && parsedCampaigns > 0) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.chat_bubble_outline_rounded, size: 12, color: AppTheme.accentColor),
                        const SizedBox(width: 4),
                        Text(
                          '$parsedCampaigns WA Campaigns',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : AppTheme.lightTextBody,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
