import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/bank_details_api.dart';

/// Rules for bank details, the same ones the server applies, so a mistake is
/// caught before the request goes out.
class BankDetailsRules {
  static final _holder = RegExp(r"^[\p{L} .'\-]+$", unicode: true);
  static final _bank = RegExp(r"^[\p{L}0-9 .&'()\-]+$", unicode: true);
  static final _account = RegExp(r'^\d{9,18}$');
  static final _ifsc = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
  static final _upi = RegExp(r'^[A-Za-z0-9.\-_]{2,256}@[A-Za-z][A-Za-z0-9]{1,63}$');

  static String clean(String v) => v.trim();
  static String cleanAccount(String v) => v.replaceAll(RegExp(r'[\s-]'), '');
  static String cleanIfsc(String v) => v.replaceAll(RegExp(r'\s'), '').toUpperCase();

  static String? holder(String v) {
    final s = clean(v);
    if (s.isEmpty) return null;
    if (s.length < 2 || s.length > 150) return 'Enter the name as it appears on the account.';
    if (!_holder.hasMatch(s)) return 'Only letters, spaces, dots, hyphens and apostrophes.';
    return null;
  }

  static String? bankName(String v) {
    final s = clean(v);
    if (s.isEmpty) return null;
    if (s.length < 2 || s.length > 150 || !_bank.hasMatch(s)) return 'Enter a valid bank name.';
    return null;
  }

  static String? account(String v) {
    final s = cleanAccount(v);
    if (s.isEmpty) return null;
    if (!_account.hasMatch(s)) return 'The account number must be 9 to 18 digits.';
    return null;
  }

  static String? ifsc(String v) {
    final s = cleanIfsc(v);
    if (s.isEmpty) return null;
    if (!_ifsc.hasMatch(s)) return 'Enter a valid IFSC code, e.g. HDFC0001234.';
    return null;
  }

  static String? upi(String v) {
    final s = v.replaceAll(RegExp(r'\s'), '');
    if (s.isEmpty) return null;
    if (s.length > 100 || !_upi.hasMatch(s)) return 'Enter a valid UPI ID, e.g. name@okhdfcbank.';
    return null;
  }
}

/// The text controllers behind a bank details form.
class BankDetailsControllers {
  final holder = TextEditingController();
  final bankName = TextEditingController();
  final account = TextEditingController();
  final confirmAccount = TextEditingController();
  final ifsc = TextEditingController();
  final upi = TextEditingController();

  /// Whether an account number is already saved, so a blank one means "keep".
  bool hasSavedAccount = false;

  List<TextEditingController> get all => [holder, bankName, account, confirmAccount, ifsc, upi];

  void fillFrom(BankDetails d) {
    holder.text = d.accountHolderName ?? '';
    bankName.text = d.bankName ?? '';
    ifsc.text = d.ifsc ?? '';
    upi.text = d.upiId ?? '';
    account.clear();
    confirmAccount.clear();
    hasSavedAccount = d.accountNumberLast4 != null;
  }

  /// Fill from a plain map, e.g. a draft.
  void fillFromMap(Map<String, dynamic> m) {
    holder.text = m['bank_account_holder_name']?.toString() ?? '';
    bankName.text = m['bank_name']?.toString() ?? '';
    account.text = m['bank_account_number']?.toString() ?? '';
    confirmAccount.text = account.text;
    ifsc.text = m['bank_ifsc']?.toString() ?? '';
    upi.text = m['bank_upi_id']?.toString() ?? '';
  }

  bool get isEmpty => all.every((c) => c.text.trim().isEmpty);

  /// The four fields a transfer needs, counting a saved account number.
  bool get coreComplete =>
      holder.text.trim().isNotEmpty &&
      bankName.text.trim().isNotEmpty &&
      ifsc.text.trim().isNotEmpty &&
      (account.text.trim().isNotEmpty || hasSavedAccount);

  bool get coreStarted =>
      holder.text.trim().isNotEmpty ||
      bankName.text.trim().isNotEmpty ||
      ifsc.text.trim().isNotEmpty ||
      account.text.trim().isNotEmpty;

  /// A form-level problem the per-field validators cannot see, or null.
  String? crossCheck({bool requireConfirm = true}) {
    if (coreStarted && !coreComplete) {
      return 'Fill in the account holder, bank name, account number and IFSC together — or leave them all empty.';
    }
    if (requireConfirm && account.text.trim().isNotEmpty &&
        BankDetailsRules.cleanAccount(account.text) != BankDetailsRules.cleanAccount(confirmAccount.text)) {
      return 'The two account numbers do not match.';
    }
    return null;
  }

  /// What to send: only filled fields, cleaned. An empty account number is
  /// left out so the saved one is kept.
  Map<String, String> toPayload() {
    final out = <String, String>{};
    void put(String key, String value) {
      if (value.isNotEmpty) out[key] = value;
    }

    put('bank_account_holder_name', BankDetailsRules.clean(holder.text));
    put('bank_name', BankDetailsRules.clean(bankName.text));
    put('bank_account_number', BankDetailsRules.cleanAccount(account.text));
    put('bank_ifsc', BankDetailsRules.cleanIfsc(ifsc.text));
    final upiValue = upi.text.replaceAll(RegExp(r'\s'), '');
    // An emptied UPI field clears it on the server.
    out['bank_upi_id'] = upiValue;
    return out;
  }

  void dispose() {
    for (final c in all) {
      c.dispose();
    }
  }
}

/// The bank details inputs, styled for any of the app's forms. Validation is
/// per field; call [BankDetailsControllers.crossCheck] before saving.
class BankDetailsFields extends StatelessWidget {
  final BankDetailsControllers controllers;
  final bool enabled;

  /// Asks for the account number twice — on by default, because a mistyped
  /// number sends a settlement to the wrong account.
  final bool confirmAccount;
  final VoidCallback? onChanged;

  const BankDetailsFields({
    super.key,
    required this.controllers,
    this.enabled = true,
    this.confirmAccount = true,
    this.onChanged,
  });

  InputDecoration _decoration(String label, IconData icon, {String? hint, String? helper}) => InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      );

  @override
  Widget build(BuildContext context) {
    final c = controllers;
    final keep = c.hasSavedAccount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const ValueKey('bank_holder'),
          controller: c.holder,
          enabled: enabled,
          textCapitalization: TextCapitalization.words,
          decoration: _decoration('Account holder name', Icons.person_outline),
          validator: (v) => BankDetailsRules.holder(v ?? ''),
          onChanged: (_) => onChanged?.call(),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('bank_name'),
          controller: c.bankName,
          enabled: enabled,
          textCapitalization: TextCapitalization.words,
          decoration: _decoration('Bank name', Icons.account_balance_outlined, hint: 'e.g. HDFC Bank'),
          validator: (v) => BankDetailsRules.bankName(v ?? ''),
          onChanged: (_) => onChanged?.call(),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('bank_account'),
          controller: c.account,
          enabled: enabled,
          keyboardType: TextInputType.number,
          obscureText: confirmAccount,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(18)],
          decoration: _decoration(
            keep ? 'New account number' : 'Account number',
            Icons.numbers,
            helper: keep ? 'Leave empty to keep the saved account.' : null,
          ),
          validator: (v) => BankDetailsRules.account(v ?? ''),
          onChanged: (_) => onChanged?.call(),
        ),
        if (confirmAccount) ...[
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('bank_account_confirm'),
            controller: c.confirmAccount,
            enabled: enabled,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(18)],
            decoration: _decoration('Re-enter account number', Icons.numbers),
            validator: (v) {
              if (c.account.text.trim().isEmpty) return null;
              return BankDetailsRules.cleanAccount(v ?? '') == BankDetailsRules.cleanAccount(c.account.text)
                  ? null
                  : 'The account numbers do not match.';
            },
            onChanged: (_) => onChanged?.call(),
          ),
        ],
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('bank_ifsc'),
          controller: c.ifsc,
          enabled: enabled,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [LengthLimitingTextInputFormatter(11)],
          decoration: _decoration('IFSC code', Icons.qr_code_2, hint: 'e.g. HDFC0001234'),
          validator: (v) => BankDetailsRules.ifsc(v ?? ''),
          onChanged: (_) => onChanged?.call(),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('bank_upi'),
          controller: c.upi,
          enabled: enabled,
          keyboardType: TextInputType.emailAddress,
          decoration: _decoration('UPI ID (optional)', Icons.alternate_email, hint: 'e.g. name@okhdfcbank'),
          validator: (v) => BankDetailsRules.upi(v ?? ''),
          onChanged: (_) => onChanged?.call(),
        ),
      ],
    );
  }
}
