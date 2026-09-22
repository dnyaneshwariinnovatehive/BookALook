import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/dashboard/more/wallet_screen.dart';
import '../services/wallet_balance.dart';
import '../theme/app_theme.dart';

/// The coin balance, as a tappable pill for a screen header.
///
/// Gold rather than the app's purple, because a balance has to read as money
/// at a glance and every app that carries one — rewards, games, wallets — uses
/// the same colour for it. Against a mostly-purple app it also separates
/// cleanly from the navigation around it.
///
/// Deliberately quiet until there is something to say: with no reading yet it
/// occupies no space at all, so a header never jumps as the balance arrives.
class WalletCoinPill extends StatelessWidget {
  final String salonId;

  /// Compact drops the word "coins" for headers that are already crowded.
  final bool compact;

  const WalletCoinPill({super.key, required this.salonId, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<WalletSnapshot?>(
      valueListenable: WalletBalance.snapshot,
      builder: (context, snapshot, _) {
        if (snapshot == null) return const SizedBox.shrink();

        final foreground = dark ? AppTheme.darkWarning : const Color(0xFFB26A00);
        final background = dark ? AppTheme.darkWarningBg : const Color(0xFFFFF4DA);

        return Semantics(
          button: true,
          label: '${snapshot.coins} reward coins, worth '
              '₹${snapshot.valueInr.toStringAsFixed(0)}. Opens your wallet.',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => WalletScreen(salonId: salonId)),
                );
                // Coins can be spent in there, so the number is re-read rather
                // than left showing what it was before.
                await WalletBalance.refresh(salonId);
              },
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: compact ? 9 : 11, vertical: compact ? 5 : 6),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: foreground.withValues(alpha: 0.22)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // A filled circle reads as a coin at 15px where a detailed
                    // icon just reads as noise.
                    Container(
                      width: compact ? 15 : 17,
                      height: compact ? 15 : 17,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFC94D), Color(0xFFF59E0B)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text('₹',
                          style: GoogleFonts.outfit(
                              fontSize: compact ? 8.5 : 9.5,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                    SizedBox(width: compact ? 5 : 6),
                    Text(snapshot.formatted,
                        style: GoogleFonts.outfit(
                            fontSize: compact ? 13 : 14,
                            fontWeight: FontWeight.w700,
                            height: 1,
                            color: foreground)),
                    if (!compact) ...[
                      const SizedBox(width: 3),
                      Text('coins',
                          style: GoogleFonts.outfit(
                              fontSize: 11,
                              height: 1,
                              fontWeight: FontWeight.w500,
                              color: foreground.withValues(alpha: 0.75))),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
