import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import 'legal_documents.dart';
import '../theme/app_colors.dart';

/// Read-only view of one of the policy documents in `legal_documents.dart`.
///
/// The text ships inside the app rather than being loaded from the website on
/// tap. That is deliberate: a customer disputing a cancellation charge should
/// be able to read the policy on a dead connection, in a basement salon with no
/// signal, and the same copy should be in the binary that was accepted at
/// sign-up.
class LegalDocumentScreen extends StatelessWidget {
  final String slug;

  const LegalDocumentScreen({Key? key, required this.slug}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final doc = legalDocumentBySlug(slug);

    // Only reachable with a bad slug if a caller is edited wrong, but a blank
    // screen with no explanation is worse than saying so.
    if (doc == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Document')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'That document could not be found.',
              style: GoogleFonts.outfit(color: context.colors.textSecondary),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(doc.title)),
      body: LegalDocumentBody(doc: doc),
    );
  }
}

/// The document itself, with no Scaffold of its own.
///
/// Split out from [LegalDocumentScreen] so the partner registration step can
/// drop a document inside its own page and its own scroll view. A partner
/// agreeing to 17 clauses should read them where they are agreeing, not have to
/// navigate away and come back to find out whether anything changed.
class LegalDocumentBody extends StatelessWidget {
  final LegalDocument doc;

  const LegalDocumentBody({Key? key, required this.doc}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final heading = context.colors.textPrimary;
    final body = context.colors.textSecondary;
    final border = context.colors.border;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        Text(
          doc.kicker.toUpperCase(),
          style: GoogleFonts.outfit(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: AppTheme.accentColor,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          doc.title,
          style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.w800, color: heading),
        ),
        const SizedBox(height: 10),
        Text(
          doc.summary,
          style: GoogleFonts.outfit(fontSize: 14, height: 1.55, color: body),
        ),
        const SizedBox(height: 24),
        for (final section in doc.sections) ..._buildSection(section, heading, body, border),
        const SizedBox(height: 8),
        _buildFooter(body, border),
      ],
    );
  }

  List<Widget> _buildSection(LegalSection section, Color heading, Color body, Color border) {
    return [
      Container(height: 1, color: border, margin: const EdgeInsets.only(top: 8, bottom: 20)),
      Text(
        section.heading,
        style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: heading),
      ),
      const SizedBox(height: 10),
      for (final block in section.blocks) ..._buildBlock(block, heading, body),
      const SizedBox(height: 20),
    ];
  }

  List<Widget> _buildBlock(LegalBlock block, Color heading, Color body) {
    final widgets = <Widget>[];

    if (block.lead != null) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text(
            block.lead!,
            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: heading),
          ),
        ),
      );
    }

    if (block.text != null) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            block.text!,
            style: GoogleFonts.outfit(fontSize: 14, height: 1.65, color: body),
          ),
        ),
      );
    }

    if (block.bullets != null) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final bullet in block.bullets!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8, right: 10),
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: AppTheme.accentColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          bullet,
                          style: GoogleFonts.outfit(fontSize: 14, height: 1.6, color: body),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _buildFooter(Color body, Color border) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: body.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Questions about this policy?',
            style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, color: body),
          ),
          const SizedBox(height: 10),
          // Letterhead order: who the letter is from, where they are, how to
          // reply. The entity name is what tells someone reading a cancellation
          // policy which company is actually behind the booking.
          Text(
            kLegalContactCompany,
            style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, color: body),
          ),
          const SizedBox(height: 4),
          Text(
            kLegalContactAddress,
            style: GoogleFonts.outfit(fontSize: 12, height: 1.5, color: body),
          ),
          const SizedBox(height: 8),
          Text(
            kLegalContactEmail,
            style: GoogleFonts.outfit(fontSize: 13, color: body, decoration: TextDecoration.underline),
          ),
        ],
      ),
    );
  }
}

/// A tappable row that opens one document. Used by the settings screens and by
/// the partner registration step's document switcher.
class LegalDocumentTile extends StatelessWidget {
  final String slug;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  const LegalDocumentTile({
    Key? key,
    required this.slug,
    this.icon,
    this.selected = false,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final doc = legalDocumentBySlug(slug);
    if (doc == null) return const SizedBox.shrink();

    final heading = context.colors.textPrimary;
    final body = context.colors.textSecondary;

    // When [onTap] is given the row is a switcher, not a link, and a check mark
    // says which document is on screen. Left to itself it navigates.
    final isSwitcher = onTap != null;

    return InkWell(
      onTap:
          onTap ??
          () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => LegalDocumentScreen(slug: slug)),
          ),
      child: Container(
        color: selected ? AppTheme.accentColor.withValues(alpha: 0.08) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: heading.withValues(alpha: 0.7)),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.title,
                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w500, color: heading),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    doc.summary,
                    maxLines: isSwitcher ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(fontSize: 12, color: body),
                  ),
                ],
              ),
            ),
            Icon(
              isSwitcher ? (selected ? Icons.radio_button_checked : Icons.radio_button_unchecked) : Icons.chevron_right,
              size: 20,
              color: selected ? AppTheme.accentColor : body.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}
