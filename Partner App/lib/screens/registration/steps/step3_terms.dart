import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../legal/legal_document_screen.dart';
import '../../../legal/legal_documents.dart';
import '../../../legal/terms_acceptance_row.dart';
import '../../../theme/app_theme.dart';

class Step3Terms extends StatefulWidget {
  final Function(Map<String, dynamic>) onSubmit;
  final VoidCallback onBack;
  final bool isLoading;

  const Step3Terms({super.key, required this.onSubmit, required this.onBack, this.isLoading = false});

  @override
  State<Step3Terms> createState() => _Step3TermsState();
}

class _Step3TermsState extends State<Step3Terms> {
  bool _agreed = false;

  /// The document on screen in the reading pane. Partner Terms opens first,
  /// because that is the contract being offered and the one this step exists to
  /// get signed; the others are there for the questions the partner actually
  /// has ("what if I cancel a job?", "what do you do with my data?").
  String _selected = 'partner-terms';

  /// Readable during registration. "About" is left out: nobody consents to a
  /// description of the company, it just pads the step.
  static const List<String> _documents = [
    'partner-terms',
    'terms',
    'privacy',
    'cancellation-refund',
  ];

  /// What the partner agrees to. Partner Terms is the binding contract; the
  /// platform Terms govern how the app works, the Privacy Policy covers the
  /// data this app collects, and Cancellation & Refund decides how much of a
  /// booking's money the salon keeps. A salon that has not read the refund rules
  /// is a salon about to argue with a customer.
  static const List<String> _consentDocuments = [
    'partner-terms',
    'terms',
    'privacy',
    'cancellation-refund',
  ];

  void _submit() {
    if (_agreed) {
      widget.onSubmit({}); // No extra data to send
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final heading = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final body = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    final selectedDoc = legalDocumentBySlug(_selected);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Terms & Conditions',
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: heading),
          ),
          const SizedBox(height: 4),
          Text(
            'Read the documents below. Registration is not possible until you accept.',
            style: GoogleFonts.outfit(fontSize: 12, color: body),
          ),
          const SizedBox(height: 16),

          // Switcher, so the partner can read everything in place instead of
          // tapping a link away and finding their way back to an enabled button.
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _documents.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final slug = _documents[i];
                final doc = legalDocumentBySlug(slug);
                if (doc == null) return const SizedBox.shrink();
                final isSelected = slug == _selected;
                return GestureDetector(
                  onTap: () => setState(() => _selected = slug),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.accentColor
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? AppTheme.accentColor : border),
                    ),
                    child: Text(
                      doc.title,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                        color: isSelected ? Colors.white : body,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          Expanded(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              // The real document, read where it is agreed to.
              child: selectedDoc == null
                  ? Center(child: Text('Document unavailable', style: GoogleFonts.outfit(color: body)))
                  : LegalDocumentBody(doc: selectedDoc),
            ),
          ),
          const SizedBox(height: 16),

          TermsAcceptanceRow(
            slugs: _consentDocuments,
            value: _agreed,
            onChanged: (v) => setState(() => _agreed = v),
            lead: 'I have read and agree to the',
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.isLoading ? null : widget.onBack,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Back', style: GoogleFonts.outfit(color: body)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _agreed && !widget.isLoading ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: _agreed
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).dividerColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: widget.isLoading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Theme.of(context).colorScheme.surface,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Register Salon'),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}
