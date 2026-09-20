import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/campaign_api.dart';
import '../../../theme/app_theme.dart';

/// Three steps: what to say, who to say it to, and a look at it before it goes.
///
/// The last step is not a formality. A campaign is irreversible the moment it
/// leaves — there is no unsending a WhatsApp message to four hundred people —
/// so the final screen shows the real audience count from the server and the
/// message exactly as it will arrive.
class NewCampaignScreen extends StatefulWidget {
  final String salonId;
  final CampaignOptions options;

  const NewCampaignScreen({Key? key, required this.salonId, required this.options})
      : super(key: key);

  @override
  State<NewCampaignScreen> createState() => _NewCampaignScreenState();
}

class _NewCampaignScreenState extends State<NewCampaignScreen> {
  int _step = 0;

  CampaignTemplate? _template;
  String _segment = 'all';
  final Map<String, String> _values = {};
  final TextEditingController _name = TextEditingController();

  AudiencePreview? _preview;
  bool _previewing = false;
  String? _previewError;
  Timer? _debounce;

  bool _sending = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    super.dispose();
  }

  void _chooseTemplate(CampaignTemplate template) {
    if (template.locked) {
      _showUpgrade('"${template.name}" is part of the Growth plan.');
      return;
    }

    setState(() {
      _template = template;
      _name.text = template.name;
      _values.clear();
      // The template knows who it is usually for; the owner can still change it.
      _segment = (template.defaultAudience?['segment'] as String?) ?? 'all';
      _step = 1;
    });

    _refreshPreview();
  }

  void _chooseSegment(AudienceSegment segment) {
    if (segment.locked) {
      _showUpgrade('Targeting "${segment.name}" is part of the Growth plan.');
      return;
    }

    setState(() => _segment = segment.key);
    _refreshPreview();
  }

  /// Ask the server who this reaches. Debounced because it fires on every
  /// change to the filters.
  void _refreshPreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() {
        _previewing = true;
        _previewError = null;
      });

      try {
        final preview = await CampaignApi.preview(widget.salonId, {'segment': _segment});
        if (!mounted) return;
        setState(() {
          _preview = preview;
          _previewing = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _previewError = e is CampaignRefused ? e.message : 'Could not count that audience.';
          _preview = null;
          _previewing = false;
        });
      }
    });
  }

  Future<void> _send() async {
    final template = _template;
    if (template == null) return;

    setState(() => _sending = true);

    try {
      await CampaignApi.send(
        salonId: widget.salonId,
        templateId: template.id,
        name: _name.text.trim().isEmpty ? template.name : _name.text.trim(),
        audience: {'segment': _segment},
        variables: _values,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Your campaign is on its way.', style: GoogleFonts.outfit()),
          backgroundColor: AppTheme.lightSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);

      if (e is CampaignRefused && e.upgradeRequired) {
        _showUpgrade(e.message);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString(), style: GoogleFonts.outfit()),
          backgroundColor: AppTheme.lightDanger,
        ),
      );
    }
  }

  void _showUpgrade(String message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppTheme.darkSurface
              : AppTheme.lightSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.workspace_premium, color: AppTheme.accentColor, size: 30),
            const SizedBox(height: 12),
            Text('Growth plan feature',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message,
                style: GoogleFonts.outfit(
                    fontSize: 14, color: AppTheme.lightTextBody, height: 1.5)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Got it',
                    style: GoogleFonts.outfit(
                        color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: dark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        title: Text(
          switch (_step) { 0 => 'Pick a campaign', 1 => 'Who should get it', _ => 'Check and send' },
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 17),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _step == 0 ? Navigator.pop(context) : setState(() => _step--),
        ),
      ),
      body: Column(
        children: [
          _stepBar(),
          Expanded(
            child: switch (_step) {
              0 => _templateStep(dark),
              1 => _audienceStep(dark),
              _ => _reviewStep(dark),
            },
          ),
          _footer(dark),
        ],
      ),
    );
  }

  Widget _stepBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          children: List.generate(3, (i) {
            return Expanded(
              child: Container(
                height: 3,
                margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                decoration: BoxDecoration(
                  color: i <= _step ? AppTheme.accentColor : AppTheme.lightBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
      );

  Widget _templateStep(bool dark) => ListView(
        padding: const EdgeInsets.all(16),
        children: widget.options.templates.map((template) {
          return Opacity(
            opacity: template.locked ? 0.6 : 1,
            child: InkWell(
              onTap: () => _chooseTemplate(template),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: dark ? AppTheme.darkSurface : AppTheme.lightSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: _template?.id == template.id
                          ? AppTheme.accentColor
                          : (dark ? AppTheme.darkBorder : AppTheme.lightBorder)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(template.name,
                                    style: GoogleFonts.outfit(
                                        fontSize: 15, fontWeight: FontWeight.w600)),
                              ),
                              if (template.locked) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.lock_outline,
                                    size: 14, color: AppTheme.accentColor),
                              ],
                            ],
                          ),
                          if (template.description != null) ...[
                            const SizedBox(height: 4),
                            Text(template.description!,
                                style: GoogleFonts.outfit(
                                    fontSize: 12.5,
                                    color: AppTheme.lightTextBody,
                                    height: 1.4)),
                          ],
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppTheme.lightTextLight),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      );

  Widget _audienceStep(bool dark) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...widget.options.segments.map((segment) {
            final selected = _segment == segment.key;

            return Opacity(
              opacity: segment.locked ? 0.6 : 1,
              child: InkWell(
                onTap: () => _chooseSegment(segment),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: selected
                        ? (dark ? AppTheme.darkAccentSoft : AppTheme.lightAccentSoft)
                        : (dark ? AppTheme.darkSurface : AppTheme.lightSurface),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: selected
                            ? AppTheme.accentColor
                            : (dark ? AppTheme.darkBorder : AppTheme.lightBorder)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected ? Icons.radio_button_checked : Icons.radio_button_off,
                        size: 18,
                        color: selected ? AppTheme.accentColor : AppTheme.lightTextLight,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(segment.name,
                                style: GoogleFonts.outfit(
                                    fontSize: 14.5, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(segment.description,
                                style: GoogleFonts.outfit(
                                    fontSize: 12, color: AppTheme.lightTextBody, height: 1.4)),
                          ],
                        ),
                      ),
                      if (segment.locked)
                        const Icon(Icons.lock_outline, size: 14, color: AppTheme.accentColor),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          _audienceCount(dark),
        ],
      );

  /// The live count. Says what it means: matched, reachable, and why the two
  /// differ.
  Widget _audienceCount(bool dark) {
    if (_previewing) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_previewError != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.lightWarningBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(_previewError!,
            style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightWarning, height: 1.4)),
      );
    }

    final preview = _preview;
    if (preview == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? AppTheme.darkAccentSoft : AppTheme.lightAccentSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${preview.willSend} customers will get this',
              style: GoogleFonts.outfit(
                  fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.accentColor)),
          if (preview.matched != preview.willSend) ...[
            const SizedBox(height: 6),
            Text('${preview.matched} matched this group.',
                style: GoogleFonts.outfit(fontSize: 12.5, color: AppTheme.lightTextBody)),
          ],
          if (preview.skipExplanation != null) ...[
            const SizedBox(height: 4),
            Text(preview.skipExplanation!,
                style: GoogleFonts.outfit(
                    fontSize: 12.5, color: AppTheme.lightTextBody, height: 1.4)),
          ],
          if (preview.beyondAllowance > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${preview.beyondAllowance} are beyond this month\'s allowance and will not be messaged.',
              style: GoogleFonts.outfit(
                  fontSize: 12.5, color: AppTheme.lightWarning, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _reviewStep(bool dark) {
    final template = _template!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _name,
          decoration: InputDecoration(
            labelText: 'Campaign name',
            helperText: 'Only you see this.',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          style: GoogleFonts.outfit(),
        ),
        const SizedBox(height: 20),

        // Only what the owner must supply. The customer's name and the salon's
        // are filled in per person by the server.
        ...template.askable.map((variable) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                decoration: InputDecoration(
                  labelText: variable.label,
                  hintText: 'e.g. ${variable.example}',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                style: GoogleFonts.outfit(),
                onChanged: (value) => setState(() => _values[variable.key] = value),
              ),
            )),

        const SizedBox(height: 8),
        Text('How it will arrive',
            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _whatsappBubble(template.render(_values)),

        const SizedBox(height: 20),
        if (_preview != null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: dark ? AppTheme.darkSurface : AppTheme.lightSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: dark ? AppTheme.darkBorder : AppTheme.lightBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.people_outline, size: 18, color: AppTheme.accentColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Going to ${_preview!.willSend} customers. This cannot be undone once sent.',
                    style: GoogleFonts.outfit(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// A WhatsApp-ish bubble, so the owner reads the message the way the customer
  /// will rather than as a row in a form.
  Widget _whatsappBubble(String text) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFDCF8C6),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomRight: Radius.circular(14),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: Text(text,
            style: GoogleFonts.outfit(
                fontSize: 13.5, color: const Color(0xFF1C1726), height: 1.5)),
      );

  Widget _footer(bool dark) {
    final canAdvance = switch (_step) {
      0 => _template != null,
      1 => (_preview?.willSend ?? 0) > 0,
      _ => !_sending,
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: !canAdvance
                ? null
                : () {
                    if (_step < 2) {
                      setState(() => _step++);
                    } else {
                      _send();
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentColor,
              disabledBackgroundColor: AppTheme.lightTextLight,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _sending
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(
                    switch (_step) {
                      0 => 'Continue',
                      1 => (_preview?.willSend ?? 0) > 0
                          ? 'Continue with ${_preview!.willSend} customers'
                          : 'Nobody to send to',
                      _ => 'Send now',
                    },
                    style: GoogleFonts.outfit(
                        color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                  ),
          ),
        ),
      ),
    );
  }
}
