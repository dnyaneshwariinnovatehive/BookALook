import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/time_window.dart';

/// The "i" beside "Select Time": the times listed are when the appointment
/// starts, not when it ends.
class SlotTimeInfoButton extends StatelessWidget {
  /// How long the chosen services take, for a worked example. 0 hides it.
  final int durationMinutes;

  /// The chosen start ("HH:mm"), if any, for the example; otherwise 10:00.
  final String? selectedStart;

  const SlotTimeInfoButton({super.key, this.durationMinutes = 0, this.selectedStart});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey('slot_time_info'),
      tooltip: 'About these times',
      visualDensity: VisualDensity.compact,
      icon: Icon(Icons.info_outline, size: 20, color: AppTheme.accentColor),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (ctx) {
          final start = selectedStart ?? '10:00';
          final end = addMinutesToClock(start, durationMinutes);
          return AlertDialog(
            title: Text('Slot times are start times', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Each time shown is when your appointment begins. Please arrive a few minutes before it.',
                  style: GoogleFonts.outfit(fontSize: 14, height: 1.4),
                ),
                if (durationMinutes > 0 && end != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Your services take about $durationMinutes minutes, so choosing '
                    '${formatClock(start)} means you are booked from ${formatTimeWindow(start, end)}.',
                    key: const ValueKey('slot_time_info_example'),
                    style: GoogleFonts.outfit(fontSize: 13.5, height: 1.4, color: ctx.colors.textSecondary),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it')),
            ],
          );
        },
      ),
    );
  }
}
