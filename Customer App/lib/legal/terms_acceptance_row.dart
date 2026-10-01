import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import 'legal_documents.dart';
import 'legal_document_screen.dart';
import '../theme/app_colors.dart';

/// The "I agree" row used at sign-up in both apps.
///
/// The document names inside the sentence are tappable and push the full text,
/// rather than being a link to a webpage. Someone ticking this box is making a
/// legal agreement, and an agreement they cannot read without a data connection
/// and a browser is worth very little.
///
/// [slugs] are the documents being agreed to, in the order they should read.
/// They are also the documents whose absence should block sign-up, so a caller
/// cannot accidentally consent to nothing.
class TermsAcceptanceRow extends StatelessWidget {
  final List<String> slugs;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String lead;

  const TermsAcceptanceRow({
    Key? key,
    required this.slugs,
    required this.value,
    required this.onChanged,
    this.lead = 'I agree to the',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final body = context.colors.textSecondary;

    final docs = slugs.map(legalDocumentBySlug).whereType<LegalDocument>().toList();
    if (docs.isEmpty) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: value,
          activeColor: AppTheme.accentColor,
          onChanged: (v) => onChanged(v ?? false),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '$lead ',
                  style: GoogleFonts.outfit(fontSize: 13, height: 1.6, color: body),
                ),
                for (var i = 0; i < docs.length; i++) ...[
                  if (i > 0)
                    Text(
                      i == docs.length - 1 ? ' and ' : ', ',
                      style: GoogleFonts.outfit(fontSize: 13, height: 1.6, color: body),
                    ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => LegalDocumentScreen(slug: docs[i].slug)),
                    ),
                    child: Text(
                      docs[i].title,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        height: 1.6,
                        color: AppTheme.accentColor,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
                Text(
                  '.',
                  style: GoogleFonts.outfit(fontSize: 13, height: 1.6, color: body),
                ),
              ],
            ),
          ),
        ),
        if (!value) ...[
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Required',
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: context.colors.danger,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
