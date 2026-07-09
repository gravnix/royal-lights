import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';

/// Confirmation dialog asked before any customer-facing WhatsApp message is
/// sent from the order flows. Returns true if the operator approves the send.
Future<bool> confirmSendCustomerWhatsApp(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final lang = Localizations.localeOf(context).languageCode;

  String tr(String key, {required String he, required String ar, required String en}) {
    final v = l10n?.tr(key);
    if (v != null && v.isNotEmpty && v != key) return v;
    return switch (lang) { 'he' => he, 'ar' => ar, _ => en };
  }

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        tr(
          'confirmSendCustomerWaTitle',
          he: 'לשלוח הודעה ללקוח?',
          ar: 'إرسال رسالة للعميل؟',
          en: 'Send message to customer?',
        ),
        style: GoogleFonts.assistant(fontWeight: FontWeight.w800),
      ),
      content: Text(
        tr(
          'confirmSendCustomerWaBody',
          he: 'האם לשלוח עדכון בוואטסאפ ללקוח?',
          ar: 'هل تريد إرسال تحديث للعميل عبر واتساب؟',
          en: 'Send a WhatsApp update to the customer?',
        ),
        style: GoogleFonts.assistant(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            tr('cancel', he: 'ביטול', ar: 'إلغاء', en: 'Cancel'),
            style: GoogleFonts.assistant(color: AppTheme.onSurfaceVariant),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.send_rounded, size: 18),
          label: Text(
            tr('send', he: 'שלח', ar: 'إرسال', en: 'Send'),
            style: GoogleFonts.assistant(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
