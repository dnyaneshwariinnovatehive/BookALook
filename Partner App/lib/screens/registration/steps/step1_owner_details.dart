import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class Step1OwnerDetails extends StatefulWidget {
  final Function(Map<String, dynamic>) onNext;
  final VoidCallback onCancel;
  final String? phone;

  const Step1OwnerDetails({super.key, required this.onNext, required this.onCancel, this.phone});

  @override
  State<Step1OwnerDetails> createState() => _Step1OwnerDetailsState();
}

class _Step1OwnerDetailsState extends State<Step1OwnerDetails> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.phone != null) {
      _phoneController.text = widget.phone!;
    }
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      widget.onNext({
        'full_name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone_number': _phoneController.text.trim(),
        'password': _passwordController.text,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Owner Account Details',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading),
            ),
            const SizedBox(height: 4),
            const Text(
              'Create your admin credentials for managing your salon.',
              style: TextStyle(fontSize: 12, color: AppTheme.lightTextBody),
            ),
            const SizedBox(height: 24),

            _buildLabel('Full Name *'),
            _buildTextField(
              controller: _nameController,
              hint: 'Full name',
              icon: Icons.person_outline,
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            _buildLabel('Email Address *'),
            _buildTextField(
              controller: _emailController,
              hint: 'name@domain.com',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (v) => !v!.contains('@') ? 'Enter a valid email' : null,
            ),
            const SizedBox(height: 16),

            _buildLabel('Phone Number *'),
            _buildTextField(
              controller: _phoneController,
              hint: 'Phone number',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            _buildLabel('Password *'),
            _buildTextField(
              controller: _passwordController,
              hint: 'Password',
              icon: Icons.lock_outline,
              obscureText: true,
              validator: (v) => v!.length < 6 ? 'Minimum 6 characters' : null,
            ),
            const SizedBox(height: 16),

            _buildLabel('Confirm Password *'),
            _buildTextField(
              controller: _confirmPasswordController,
              hint: 'Confirm password',
              icon: Icons.lock_outline,
              obscureText: true,
              validator: (v) => v != _passwordController.text ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: 32),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: AppTheme.lightBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel', style: TextStyle(color: AppTheme.lightTextBody)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Next'),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.black26),
        prefixIcon: Icon(icon, color: Colors.black38, size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.accentColor)),
      ),
    );
  }
}
