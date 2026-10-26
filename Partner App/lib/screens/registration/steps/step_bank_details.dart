import 'package:flutter/material.dart';

import '../../../services/bank_details_api.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/bank_details_fields.dart';
import '../../../widgets/same_bank_as_other_salon.dart';

/// Optional registration step: where BookALook should send the salon's money.
///
/// Skippable outright — a salon registers, and can go live, without it — and
/// the owner can add the details later from More → Bank Details.
class StepBankDetails extends StatefulWidget {
  final void Function(Map<String, dynamic>) onNext;
  final VoidCallback onBack;

  /// An owner adding another branch: offer "Same as my other salon" when one
  /// of their salons already has complete details.
  final bool offerSaved;

  /// Test seam; defaults to the real API.
  final Future<List<OtherSalonBank>> Function()? loadSaved;

  const StepBankDetails({
    super.key,
    required this.onNext,
    required this.onBack,
    this.offerSaved = false,
    this.loadSaved,
  });

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
    'bank_copy_from_salon_id': null,
  };

  List<OtherSalonBank> _saved = const [];

  /// The salon whose account this branch will reuse, when chosen.
  OtherSalonBank? _copyFrom;

  @override
  void initState() {
    super.initState();
    if (widget.offerSaved) _loadSaved();
  }

  Future<void> _loadSaved() async {
    final saved = await (widget.loadSaved ?? BankDetailsApi.savedAccounts)();
    if (mounted) setState(() => _saved = saved);
  }

  Future<void> _chooseSaved() async {
    final picked = _saved.length == 1 ? _saved.first : await pickOtherSalonBank(context, _saved);
    if (picked != null && mounted) {
      setState(() {
        _copyFrom = picked;
        _error = null;
      });
    }
  }

  @override
  void dispose() {
    _fields.dispose();
    super.dispose();
  }

  void _skip() => widget.onNext(Map<String, dynamic>.from(_cleared));

  void _continue() {
    setState(() => _error = null);
    if (_copyFrom != null) {
      widget.onNext({...Map<String, dynamic>.from(_cleared), 'bank_copy_from_salon_id': _copyFrom!.salonId});
      return;
    }
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
          if (_copyFrom != null)
            _copyingCard(_copyFrom!)
          else ...[
            if (_saved.isNotEmpty) ...[
              SameBankAsOtherSalonButton(onPressed: _chooseSaved),
              const SizedBox(height: 4),
              Center(
                child: Text('or enter the details below', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ),
              const SizedBox(height: 14),
            ],
            BankDetailsFields(controllers: _fields),
          ],
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

  Widget _copyingCard(OtherSalonBank source) {
    return Container(
      key: const ValueKey('reg_bank_copying'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppTheme.accentColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Same as ${source.salonName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(describeBankAccount(source.details), style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          TextButton(
            key: const ValueKey('reg_bank_copy_change'),
            onPressed: () => setState(() => _copyFrom = null),
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}
