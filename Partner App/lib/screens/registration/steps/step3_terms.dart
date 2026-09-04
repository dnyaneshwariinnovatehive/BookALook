import 'package:partner_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../../../../theme/app_theme.dart';

class Step3Terms extends StatefulWidget {
  final Function(Map<String, dynamic>) onSubmit;
  final VoidCallback onBack;
  final bool isLoading;

  const Step3Terms({super.key, required this.onSubmit, required this.onBack, this.isLoading = false});

  @override
  State<Step3Terms> createState() => _Step3TermsState();
}

class _Step3TermsState extends State<Step3Terms> {
  bool _agreed = false;

  void _submit() {
    if (_agreed) {
      widget.onSubmit({}); // No extra data to send
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Terms & Conditions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading),
          ),
          const SizedBox(height: 4),
          Text(
            'Please review and accept the partner terms.',
            style: TextStyle(fontSize: 12, color: AppTheme.lightTextBody),
          ),
          const SizedBox(height: 24),
          
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.lightBorder),
              ),
              child: const SingleChildScrollView(
                child: Text(
                  '''SalonHub Partner Terms & Conditions
1. By registering as a SalonHub partner, you agree to provide accurate and up-to-date information about your salon, services, and pricing.
2. You authorize SalonHub to list your salon on the platform and allow customers to book appointments through the app.
3. You agree to honor the prices and services listed on your SalonHub profile.
4. You are responsible for maintaining the confidentiality of your admin account credentials.
5. SalonHub reserves the right to suspend or remove your listing in case of violations of platform policies.
6. You agree to provide quality service to all customers who book through the platform.
7. Commissions and payment terms will be communicated separately via the admin dashboard.
8. You may update your salon profile, services, and availability at any time through the admin dashboard.
9. SalonHub may use your salon's name and images for promotional purposes on the platform.
10. These terms may be updated from time to time. Continued use of the platform constitutes acceptance of updated terms.''',
                  style: TextStyle(fontSize: 12, color: AppTheme.lightTextBody, height: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          Row(
            children: [
              Checkbox(
                value: _agreed,
                activeColor: AppTheme.accentColor,
                onChanged: (val) => setState(() => _agreed = val ?? false),
              ),
              const Expanded(
                child: Text('I agree to the SalonHub Partner Terms & Conditions', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 32),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.isLoading ? null : widget.onBack,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: AppTheme.lightBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Back', style: TextStyle(color: AppTheme.lightTextBody)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _agreed && !widget.isLoading ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: _agreed ? Theme.of(context).colorScheme.onSurface : Theme.of(context).dividerColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: widget.isLoading 
                      ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Theme.of(context).colorScheme.surface, strokeWidth: 2))
                      : Text('Register Salon'),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}
