import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class DeactivateSalonButton extends StatelessWidget {
  const DeactivateSalonButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.5)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _handleDeactivateAccount(context),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.red),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Deactivate Account',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleDeactivateAccount(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Deactivate Salon', style: GoogleFonts.outfit(color: Colors.red, fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to deactivate your salon? This action will hide your salon from customers.',
          style: GoogleFonts.outfit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.outfit()),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _processDeactivation(context, false);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: Text('Deactivate', style: GoogleFonts.outfit(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _processDeactivation(BuildContext context, bool forceCloseSchedule) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );

      final auth = AuthService();
      final user = await auth.getUser();
      final salonId = user?['salon_id'];

      if (salonId == null) {
        Navigator.pop(context);
        Fluttertoast.showToast(msg: 'Salon not found.');
        return;
      }

      final payload = {'force_close_schedule': forceCloseSchedule};
      final response = await ApiService.post('/salons/$salonId/deactivate', payload);

      if (context.mounted) Navigator.pop(context); // close loader

      if (response.statusCode == 200) {
        Fluttertoast.showToast(msg: 'Salon deactivated successfully.');
        AuthService().logout(context);
      } else {
        final data = response.data;
        if (data != null && data['error_code'] == 'HAS_UPCOMING_APPOINTMENTS' && !forceCloseSchedule) {
          if (context.mounted) _showForceCloseDialog(context, data['message']);
        } else {
          Fluttertoast.showToast(msg: data?['message'] ?? 'Failed to deactivate salon', toastLength: Toast.LENGTH_LONG);
        }
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      Fluttertoast.showToast(msg: 'An error occurred. Please try again.');
    }
  }

  void _showForceCloseDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Upcoming Appointments', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          '$message\n\nWould you like to automatically close your salon schedule so no new customers can book while you finish them?',
          style: GoogleFonts.outfit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.outfit()),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _processDeactivation(context, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: Text('Close Schedule', style: GoogleFonts.outfit(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
