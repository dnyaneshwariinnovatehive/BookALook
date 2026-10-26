import 'package:flutter/material.dart';

import '../services/bank_details_api.dart';
import '../theme/app_theme.dart';

/// "Same as my other salon": the button an owner with more than one branch
/// taps to reuse an account already saved at another of their salons.
class SameBankAsOtherSalonButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const SameBankAsOtherSalonButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const ValueKey('bank_same_as_other'),
      onPressed: onPressed,
      icon: const Icon(Icons.copy_all_outlined, size: 18),
      label: const Text('Same as my other salon'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.accentColor,
        side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.5)),
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// One line describing a saved account: "HDFC Bank •••• 1234 · HDFC0001234".
String describeBankAccount(BankDetails d) {
  final parts = <String>[
    [d.bankName, d.maskedAccount].where((s) => s != null && s.isNotEmpty).join(' '),
    if (d.ifsc != null) d.ifsc!,
  ].where((s) => s.isNotEmpty);
  return parts.join(' · ');
}

/// Lets the owner pick which of their salons to copy from. Returns null when
/// they close the sheet.
Future<OtherSalonBank?> pickOtherSalonBank(BuildContext context, List<OtherSalonBank> salons) {
  return showModalBottomSheet<OtherSalonBank>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('Use bank details from', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Settlements for this salon will go to the same account.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          for (final salon in salons)
            ListTile(
              key: ValueKey('bank_copy_option_${salon.salonId}'),
              leading: const CircleAvatar(
                backgroundColor: Color(0x1A000000),
                child: Icon(Icons.storefront, color: AppTheme.accentColor),
              ),
              title: Text(salon.salonName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                [
                  describeBankAccount(salon.details),
                  if (salon.details.accountHolderName != null) salon.details.accountHolderName!,
                ].join('\n'),
              ),
              isThreeLine: salon.details.accountHolderName != null,
              onTap: () => Navigator.pop(ctx, salon),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
