import 'package:flutter/material.dart';

import '../../../services/bank_details_api.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/bank_details_fields.dart';

/// The salon owner's bank details: where BookALook sends their settlements.
///
/// Saving asks first — the details decide where real money goes — and says
/// plainly when it would replace what is already saved. Leaving with unsaved
/// edits asks too. Pops with true once the server has confirmed a save.
class BankDetailsScreen extends StatefulWidget {
  final String salonId;

  /// Test seams; default to the real API.
  final Future<BankDetailsStatus> Function(String salonId)? load;
  final Future<BankDetailsStatus> Function(String salonId, Map<String, String> fields)? save;

  const BankDetailsScreen({super.key, required this.salonId, this.load, this.save});

  @override
  State<BankDetailsScreen> createState() => _BankDetailsScreenState();
}

class _BankDetailsScreenState extends State<BankDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fields = BankDetailsControllers();

  BankDetails _saved = const BankDetails();
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _loadError;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fields.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final status = await (widget.load ?? BankDetailsApi.fetch)(widget.salonId);
      if (!mounted) return;
      setState(() {
        _saved = status.details;
        _fields.fillFrom(status.details);
        _dirty = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<bool?> _confirm({required String title, required String message, required String confirmLabel}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(key: const ValueKey('bank_confirm_cancel'), onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            key: const ValueKey('bank_confirm_ok'),
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor, foregroundColor: Colors.white),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _formError = null);

    if (!(_formKey.currentState?.validate() ?? false)) return;
    final problem = _fields.crossCheck();
    if (problem != null) {
      setState(() => _formError = problem);
      return;
    }
    if (!_fields.coreComplete) {
      setState(() => _formError = 'Add the account holder, bank name, account number and IFSC to receive settlements.');
      return;
    }

    final replacing = _saved.hasRequired;
    final ok = await _confirm(
      title: replacing ? 'Replace saved bank details?' : 'Save bank details?',
      message: replacing
          ? 'Your saved details (${_saved.bankName ?? 'bank'} ${_saved.maskedAccount}) will be replaced. '
              'Future settlements from BookALook will go to the new details.'
          : 'Are you sure you want to save these bank details? BookALook will send your settlements to this account.',
      confirmLabel: replacing ? 'Replace' : 'Confirm',
    );
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final status = await (widget.save ?? BankDetailsApi.save)(widget.salonId, _fields.toPayload());
      if (!mounted) return;
      setState(() {
        _saved = status.details;
        _fields.fillFrom(status.details);
        _dirty = false;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text(replacing ? 'Bank details updated.' : 'Bank details saved.'),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty || _saving) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your bank details have not been saved. Leave and lose the changes?'),
        actions: [
          TextButton(key: const ValueKey('bank_leave_stay'), onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          TextButton(
            key: const ValueKey('bank_leave_discard'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return discard == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && mounted) {
          setState(() => _dirty = false);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Bank details')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? _error()
                : _form(),
      ),
    );
  }

  Widget _error() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );

  Widget _form() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline, color: AppTheme.accentColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _saved.hasRequired
                        ? 'Settlements go to ${_saved.bankName} ${_saved.maskedAccount} (${_saved.ifsc}).'
                        : 'BookALook collects advances from your customers and sends them to this account. '
                            'The full account number is never shown again after saving.',
                    key: const ValueKey('bank_summary'),
                    style: const TextStyle(fontSize: 13, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          BankDetailsFields(
            controllers: _fields,
            enabled: !_saving,
            onChanged: () {
              if (!_dirty) setState(() => _dirty = true);
            },
          ),
          if (_formError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_formError!, key: const ValueKey('bank_form_error'), style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              key: const ValueKey('bank_save'),
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor, foregroundColor: Colors.white),
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_saved.hasRequired ? 'Update bank details' : 'Save bank details',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}
