import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../services/salon_support_api.dart';
import '../theme/app_theme.dart';

/// Writing to BookALook — about a settlement, a payout, a renewal — and
/// reading its replies. Replies also arrive as notifications.
class ContactBookALookScreen extends StatefulWidget {
  final String salonId;

  /// Open settlements the message can be about.
  final List<OpenSettlement> settlements;

  @visibleForTesting
  final Future<(List<SupportTopic>, List<SupportRequest>)> Function(String salonId)? loader;

  @visibleForTesting
  final Future<String> Function(String salonId, String topic, String message, String? payoutId)? sender;

  const ContactBookALookScreen({
    super.key,
    required this.salonId,
    this.settlements = const [],
    this.loader,
    this.sender,
  });

  @override
  State<ContactBookALookScreen> createState() => _ContactBookALookScreenState();
}

class _ContactBookALookScreenState extends State<ContactBookALookScreen> {
  final _message = TextEditingController();
  List<SupportTopic> _topics = SalonSupportApi.defaultTopics;
  List<SupportRequest> _history = [];
  String _topic = 'settlement_query';
  String? _payoutId;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.settlements.isEmpty) _topic = 'renewal_help';
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final (topics, history) = await (widget.loader ?? SalonSupportApi.requests)(widget.salonId);
      if (!mounted) return;
      setState(() {
        _topics = topics;
        _history = history;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _aboutSettlement => _topic == 'settlement_query' || _topic == 'payout_request';

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.length < 5) {
      setState(() => _error = 'Write a little more so BookALook knows how to help.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final payoutId = _aboutSettlement ? _payoutId : null;
      final sent = widget.sender != null
          ? await widget.sender!(widget.salonId, _topic, text, payoutId)
          : await SalonSupportApi.send(widget.salonId, topic: _topic, message: text, payoutId: payoutId);
      if (!mounted) return;
      _message.clear();
      setState(() {
        _sending = false;
        _payoutId = null;
      });
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sent)));
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String _inr(double v) => NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(v);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: Text('Contact BookALook', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('What is it about?', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _topics)
                  ChoiceChip(
                    key: ValueKey('topic-${t.key}'),
                    label: Text(t.label),
                    selected: _topic == t.key,
                    onSelected: (_) => setState(() => _topic = t.key),
                    selectedColor: AppTheme.accentColor.withValues(alpha: 0.15),
                    labelStyle: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _topic == t.key ? AppTheme.accentColor : AppTheme.lightTextHeading,
                    ),
                  ),
              ],
            ),
            if (_aboutSettlement && widget.settlements.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Which settlement? (optional)',
                  style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                key: const ValueKey('contact_settlement'),
                initialValue: _payoutId,
                isExpanded: true,
                decoration: _box(),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Not about one in particular')),
                  for (final s in widget.settlements)
                    DropdownMenuItem<String?>(
                      value: s.id,
                      child: Text(
                        '${s.label} · ${s.salonOwes ? 'you owe' : 'owed to you'} ${_inr(s.amount)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _payoutId = v),
              ),
            ],
            const SizedBox(height: 16),
            Text('Your message', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('contact_message'),
              controller: _message,
              minLines: 4,
              maxLines: 8,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: _box(hint: 'Tell BookALook what you need — e.g. "Please release my payout for last week."'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('contact_send'),
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(_sending ? 'Sending…' : 'Send to BookALook'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text('You will get a notification when BookALook replies.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextBody)),
            const SizedBox(height: 26),
            Text('Your messages', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
            else if (_history.isEmpty)
              Text('Nothing sent yet.', style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightTextBody))
            else
              for (final r in _history) _historyCard(r),
          ],
        ),
      ),
    );
  }

  Widget _historyCard(SupportRequest r) {
    final when = r.createdAt == null ? '' : DateFormat('d MMM, h:mm a').format(r.createdAt!);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(r.topicLabel, style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.bold)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: r.isOpen ? AppTheme.lightWarning.withValues(alpha: 0.15) : AppTheme.lightSuccessBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  r.isOpen ? (r.reply == null ? 'Waiting' : 'Replied') : 'Resolved',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: r.isOpen ? AppTheme.lightWarning : AppTheme.lightSuccess,
                  ),
                ),
              ),
            ],
          ),
          if (when.isNotEmpty)
            Text(when, style: GoogleFonts.outfit(fontSize: 11, color: AppTheme.lightTextLight)),
          const SizedBox(height: 6),
          Text(r.message, style: GoogleFonts.outfit(fontSize: 13, height: 1.4)),
          if (r.reply != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.accentColor.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('BookALook replied',
                      style: GoogleFonts.outfit(
                          fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.accentColor)),
                  const SizedBox(height: 3),
                  Text(r.reply!, style: GoogleFonts.outfit(fontSize: 13, height: 1.4)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _box({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: AppTheme.lightTextLight),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.lightBorder),
        ),
      );
}
