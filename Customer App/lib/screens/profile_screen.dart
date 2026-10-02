import 'package:flutter/material.dart';
import '../legal/terms_acceptance_row.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/city_area_picker.dart';
import '../widgets/feedback_states.dart';
import 'main_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String phone;
  final bool isModal;
  final int returnIndex;

  const ProfileScreen({Key? key, required this.phone, this.isModal = false, this.returnIndex = 0}) : super(key: key);

  /// Inline messages, for tests: the location problem under the picker, and
  /// a failed submit above the button.
  static const Key locationErrorKey = Key('profile-location-error');
  static const Key submitErrorKey = Key('profile-submit-error');

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _dobController = TextEditingController();
  final _addressController = TextEditingController();
  final _authService = AuthService();
  
  bool _isLoading = false;
  String _selectedGender = 'unspecified';

  /// Each problem is shown next to the thing it is about, not in a SnackBar:
  /// this is a form, the keyboard is often up, and a SnackBar would vanish
  /// before someone scrolled to the field it meant.
  String? _nameError;
  String? _dobError;
  String? _locationError;
  String? _submitError;

  /// Not sent to the backend — the app has no consent table, and the email and
  /// address in the policy documents are the record. This is here so the box
  /// cannot be ticked by default and so sign-up genuinely stops until it is.
  bool _acceptedTerms = false;

  /// The documents a customer agrees to at sign-up. The full platform Terms of
  /// Use, the Privacy Policy, and the policy that actually decides whether they
  /// get their money back.
  static const List<String> _consentDocuments = [
    'terms',
    'privacy',
    'cancellation-refund',
  ];

  // Where they are. Required at sign-up so the first screen they see can show
  // what is actually near them.
  String? _cityId;
  String? _subAreaId;

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(Duration(days: 365 * 18)), // Default to 18 years old
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _dobError = null;
        _dobController.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  void _completeProfile() async {
    final name = _nameController.text.trim();
    final dob = _dobController.text.trim();

    // Every missing field at once, so fixing one does not uncover the next.
    setState(() {
      _nameError = name.isEmpty ? 'Name is required' : null;
      _dobError = dob.isEmpty ? 'Date of Birth is required' : null;
      _locationError = _cityId == null
          ? 'Please choose your city'
          : (_subAreaId == null ? 'Please choose your area' : null);
      _submitError = _acceptedTerms ? null : 'Please read and accept the terms to continue';
    });
    if (_nameError != null || _dobError != null || _locationError != null || _submitError != null) {
      return;
    }

    setState(() => _isLoading = true);

    final success = await _authService.completeProfile(
      widget.phone,
      name,
      _selectedGender,
      _dobController.text.trim(),
      _addressController.text.trim(),
      cityId: _cityId,
      subAreaId: _subAreaId,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      if (widget.isModal) {
        Navigator.pop(context, true);
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => MainScreen(initialIndex: widget.returnIndex)),
          (route) => false,
        );
      }
    } else {
      setState(() => _submitError = 'We could not create your account. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.pageNeutral,
      appBar: AppBar(
        backgroundColor: context.colors.pageNeutral,
        elevation: 0,
        title: Text(
          'Complete Profile',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: context.colors.textPrimary,
          ),
        ),
        iconTheme: IconThemeData(color: context.colors.textPrimary),
      ),
      body: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: context.colors.surface,
            labelStyle: GoogleFonts.outfit(color: context.colors.textSecondary),
            prefixIconColor: AppTheme.accentColor.withValues(alpha: 0.6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.accentColor, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.colors.danger, width: 1),
            ),
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Welcome!',
              style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: context.colors.textPrimary),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Please provide your details to continue.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 15, color: context.colors.textSecondary),
            ),
            SizedBox(height: 32),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
              decoration: InputDecoration(
                labelText: 'Full Name *',
                errorText: _nameError,
                prefixIcon: Icon(Icons.person),
              ),
            ),
            SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedGender,
              decoration: InputDecoration(
                labelText: 'Gender',
                prefixIcon: Icon(Icons.group),
              ),
              items: [
                DropdownMenuItem(value: 'unspecified', child: Text('Prefer not to say', style: GoogleFonts.outfit())),
                DropdownMenuItem(value: 'male', child: Text('Male', style: GoogleFonts.outfit())),
                DropdownMenuItem(value: 'female', child: Text('Female', style: GoogleFonts.outfit())),
                DropdownMenuItem(value: 'other', child: Text('Other', style: GoogleFonts.outfit())),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedGender = value);
                }
              },
            ),
            SizedBox(height: 16),
            CityAreaPicker(
              onChanged: (cityId, subAreaId) {
                setState(() {
                  _cityId = cityId;
                  _subAreaId = subAreaId;
                  _locationError = null;
                });
              },
            ),
            if (_locationError != null) ...[
              SizedBox(height: 8),
              InlineStatus(
                key: ProfileScreen.locationErrorKey,
                message: _locationError!,
                kind: StatusKind.warning,
              ),
            ],
            SizedBox(height: 16),
            TextField(
              controller: _dobController,
              readOnly: true,
              onTap: () => _selectDate(context),
              decoration: InputDecoration(
                labelText: 'Date of Birth (YYYY-MM-DD) *',
                errorText: _dobError,
                prefixIcon: Icon(Icons.calendar_today),
              ),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _addressController,
              decoration: InputDecoration(
                labelText: 'Address',
                prefixIcon: Icon(Icons.home),
              ),
              maxLines: 3,
            ),
            SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TermsAcceptanceRow(
                slugs: _consentDocuments,
                value: _acceptedTerms,
                onChanged: (v) => setState(() {
                  _acceptedTerms = v;
                  if (v) _submitError = null;
                }),
              ),
            ),
            SizedBox(height: 24),
            if (_submitError != null) ...[
              InlineStatus(
                key: ProfileScreen.submitErrorKey,
                message: _submitError!,
                onRetry: _acceptedTerms && !_isLoading ? _completeProfile : null,
              ),
              SizedBox(height: 12),
            ],
            ElevatedButton(
              onPressed: (_isLoading || !_acceptedTerms) ? null : _completeProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                padding: EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
              ),
              child: _isLoading 
                ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('Complete & Login', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
            Text(
              'By completing your profile you are creating a BooKalook account. '
              'We use your phone number, name and location to show you salons near you.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 11.5,
                height: 1.5,
                color: context.colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
