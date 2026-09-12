import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/collaborator_api.dart';
import '../../../theme/app_theme.dart';

/// Editing the collaborator's own contact details.
///
/// Phone is shown but locked. It is the whole of their login — there is no
/// password and no email fallback — so letting it be changed from inside the
/// app would be handing someone a way to lock themselves out permanently. A
/// change there has to go through SuperAdmin.
class EditCollaboratorProfileSheet extends StatefulWidget {
  final Map<String, dynamic> profile;

  const EditCollaboratorProfileSheet({super.key, required this.profile});

  @override
  State<EditCollaboratorProfileSheet> createState() => _EditCollaboratorProfileSheetState();
}

class _EditCollaboratorProfileSheetState extends State<EditCollaboratorProfileSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _pincode;

  String _gender = 'unspecified';
  DateTime? _dob;

  bool _saving = false;
  String? _error;

  static const _genders = {
    'unspecified': 'Prefer not to say',
    'male': 'Male',
    'female': 'Female',
    'other': 'Other',
  };

  @override
  void initState() {
    super.initState();

    _name = TextEditingController(text: widget.profile['name']?.toString() ?? '');
    _email = TextEditingController(text: widget.profile['email']?.toString() ?? '');
    _address = TextEditingController(text: widget.profile['address']?.toString() ?? '');
    _pincode = TextEditingController(text: widget.profile['pincode']?.toString() ?? '');

    final gender = widget.profile['gender']?.toString();
    if (gender != null && _genders.containsKey(gender)) _gender = gender;

    _dob = DateTime.tryParse(widget.profile['date_of_birth']?.toString() ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _address.dispose();
    _pincode.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 90),
      lastDate: now.subtract(const Duration(days: 1)),
    );

    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await CollaboratorApi.updateProfile({
        'name': _name.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'gender': _gender,
        'date_of_birth': _dob == null ? null : DateFormat('yyyy-MM-dd').format(_dob!),
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'pincode': _pincode.text.trim().isEmpty ? null : _pincode.text.trim(),
      });

      if (mounted) Navigator.pop(context, true);
    } on OnboardingRejected catch (e) {
      // The server's own wording — "that email is already taken" beats "failed".
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No connection. Your profile was not saved.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      decoration: const BoxDecoration(
        color: AppTheme.lightBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.lightBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text('Your details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 18),

              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.lightDangerBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline, size: 17, color: AppTheme.lightDanger),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(_error!,
                            style: const TextStyle(
                                fontSize: 12.5, height: 1.4, color: AppTheme.lightDanger)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              _label('Name *'),
              _field(
                _name,
                'Your full name',
                Icons.person_outline,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Your name is required' : null,
              ),
              const SizedBox(height: 14),

              _label('Phone'),
              _buildLockedPhone(),
              const SizedBox(height: 14),

              _label('Email'),
              _field(_email, 'Optional', Icons.alternate_email,
                  keyboard: TextInputType.emailAddress,
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) return null;
                    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)
                        ? null
                        : 'That does not look like an email address';
                  }),
              const SizedBox(height: 14),

              _label('Gender'),
              DropdownButtonFormField<String>(
                initialValue: _gender,
                isExpanded: true,
                items: _genders.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (value) => setState(() => _gender = value ?? 'unspecified'),
                decoration: _decoration(null, Icons.wc_outlined),
              ),
              const SizedBox(height: 14),

              _label('Date of birth'),
              GestureDetector(
                onTap: _pickDob,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.lightBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cake_outlined, size: 19, color: AppTheme.lightTextLight),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _dob == null
                              ? 'Not set'
                              : DateFormat('d MMMM yyyy').format(_dob!),
                          style: TextStyle(
                            fontSize: 13.5,
                            color: _dob == null
                                ? AppTheme.lightTextLight
                                : AppTheme.lightTextHeading,
                          ),
                        ),
                      ),
                      if (_dob != null)
                        GestureDetector(
                          onTap: () => setState(() => _dob = null),
                          child: const Icon(Icons.close,
                              size: 17, color: AppTheme.lightTextLight),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              _label('Address'),
              _field(_address, 'Where you are based', Icons.home_outlined, lines: 2),
              const SizedBox(height: 14),

              _label('Pincode'),
              _field(_pincode, '6 digits', Icons.pin_drop_outlined,
                  keyboard: TextInputType.number,
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) return null;
                    return RegExp(r'^\d{4,10}$').hasMatch(value)
                        ? null
                        : 'That does not look like a pincode';
                  }),

              const SizedBox(height: 26),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        side: const BorderSide(color: AppTheme.lightBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel',
                          style: TextStyle(color: AppTheme.lightTextBody)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        backgroundColor: AppTheme.accentColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Save',
                              style:
                                  TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLockedPhone() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
        decoration: BoxDecoration(
          color: AppTheme.lightBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.lightBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.smartphone_outlined, size: 19, color: AppTheme.lightTextLight),
            const SizedBox(width: 12),
            Expanded(
              child: Text(widget.profile['phone']?.toString() ?? '',
                  style: const TextStyle(fontSize: 13.5, color: AppTheme.lightTextBody)),
            ),
            const Icon(Icons.lock_outline, size: 16, color: AppTheme.lightTextLight),
          ],
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      );

  Widget _field(
    TextEditingController controller,
    String hint,
    IconData icon, {
    TextInputType? keyboard,
    int lines = 1,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboard,
        maxLines: lines,
        validator: validator,
        decoration: _decoration(hint, icon),
      );

  InputDecoration _decoration(String? hint, IconData icon) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.lightTextLight, fontSize: 13.5),
        prefixIcon: Icon(icon, size: 19, color: AppTheme.lightTextLight),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        border: _border(AppTheme.lightBorder),
        enabledBorder: _border(AppTheme.lightBorder),
        focusedBorder: _border(AppTheme.accentColor),
        errorBorder: _border(AppTheme.lightDanger),
        focusedErrorBorder: _border(AppTheme.lightDanger),
      );

  OutlineInputBorder _border(Color colour) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colour),
      );
}
