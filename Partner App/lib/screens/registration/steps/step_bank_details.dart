import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/bank_details_fields.dart';

/// Optional registration step: where BookALook should send the salon's money.
///
/// Skippable outright — a salon registers, and can go live, without it — and
/// the owner can add the details later from More → Bank Details.
class StepBankDetails extends StatefulWidget {
  final void Function(Map<String, dynamic>) onNext;
  final VoidCallback onBack;

  const StepBankDetails({super.key, required this.onNext, required this.onBack});

  @override
  State<StepBankDetails> createState() => _StepBankDetailsState();
}

class _StepBankDetailsState extends State<StepBankDetails> {
  final _formKey = GlobalKey<FormState>();
  final _fields = BankDetailsControllers();
  String? _error;

  /// Every bank key, emptied: skipping after typing something must not send
  /// what was typed.
  static const Map<String, dynamic> _cleared = {
    'bank_account_holder_name': null,
    'bank_name': null,
    'bank_account_number': null,
    'bank_ifsc': null,
    'bank_upi_id': null,
  };

  @override
  void dispose() {
    _fields.dispose();
    super.dispose();
  }

  void _skip() => widget.onNext(Map<String, dynamic>.from(_cleared));

  void _continue() {
    setState(() => _error = null);
    if (_fields.isEmpty) {
      _skip();
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final problem = _fields.crossCheck();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    widget.onNext({...Map<String, dynamic>.from(_cleared), ..._fields.toPayload()});
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Bank details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            'Optional. BookALook collects advances from your customers and sends your settlements to this account. '
            'You can skip this and add it later from More → Bank Details.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 18),
          BankDetailsFields(controllers: _fields),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, key: const ValueKey('reg_bank_error'), style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: widget.onBack, child: const Text('Back')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  key: const ValueKey('reg_bank_continue'),
                  onPressed: _continue,
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor, foregroundColor: Colors.white),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              key: const ValueKey('reg_bank_skip'),
              onPressed: _skip,
              child: const Text('Skip for now'),
            ),
          ),
        ],
      ),
    );
  }
}
