import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../legal/legal_document_screen.dart';
import '../legal/legal_documents.dart';
import '../theme/app_theme.dart';

/// Fills the "Help & Support" row in the More tab, which previously did nothing
/// when tapped.
///
/// Two things a partner needs and cannot find elsewhere in the app: a way to
/// reach a human, and the documents that say what the platform expects of them
/// and what it does with their data. A registered partner has to be able to
/// re-read the terms they accepted without going through registration again.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  /// All five documents. Unlike the customer side, "About" is included — a
  /// partner is a business counterparty here, not just a user of the app.
  static const Map<String, IconData> _documents = {
    'partner-terms': Icons.handshake_outlined,
    'terms': Icons.gavel_outlined,
    'privacy': Icons.lock_outline,
    'cancellation-refund': Icons.event_busy_outlined,
    'about': Icons.info_outline,
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final heading = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final body = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final surface = Theme.of(context).colorScheme.surface;

    return Scaffold(
      appBar: AppBar(
        title: Text('Help & Support', style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _SectionLabel('CONTACT US'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Registered entity',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: AppTheme.accentColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  kLegalContactCompany,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: heading,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  kLegalContactAddress,
                  style: GoogleFonts.outfit(fontSize: 13, height: 1.55, color: body),
                ),
                const SizedBox(height: 16),
                Text(
                  'Email us',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: body.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  kLegalContactEmail,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: heading,
                    decoration: TextDecoration.underline,
                    decorationColor: AppTheme.accentColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _SectionLabel('POLICIES & TERMS'),
          const SizedBox(height: 4),
          Text(
            'Saved in the app, so these open without a connection.',
            style: GoogleFonts.outfit(fontSize: 12, color: body.withOpacity(0.8)),
          ),
          const SizedBox(height: 12),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border),
            ),
            child: Column(
              children: [
                for (final entry in _documents.entries) ...[
                  LegalDocumentTile(slug: entry.key, icon: entry.value),
                  if (entry.key != _documents.keys.last) Divider(height: 1, color: border),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),
          Center(
            child: Text(
              'BooKalook',
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: body.withOpacity(0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _SectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: AppTheme.accentColor,
        ),
      ),
    );
  }
}
