import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/quote.dart';

String _trOrLocale(
  BuildContext context,
  AppLocalizations? l10n,
  String key, {
  required String en,
  required String he,
  required String ar,
}) {
  final t = l10n?.tr(key) ?? '';
  if (t.isNotEmpty && t != key) return t;
  return switch (Localizations.localeOf(context).languageCode) {
    'he' => he,
    'ar' => ar,
    _ => en,
  };
}

/// In-app quote PDF viewer with open / download / print actions.
Future<void> showQuotePdfPreview(
  BuildContext context, {
  required Quote quote,
  AppLocalizations? l10n,
}) async {
  final url = quote.pdfUrl?.trim() ?? '';
  if (url.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _trOrLocale(context, l10n, 'quotePdfMissing',
              en: 'Quote PDF is not available.',
              he: 'קובץ הצעת המחיר אינו זמין.',
              ar: 'ملف عرض السعر غير متوفر.'),
          style: GoogleFonts.assistant(),
        ),
        backgroundColor: AppTheme.error,
      ),
    );
    return;
  }

  final title = _trOrLocale(
    context,
    l10n,
    'viewQuoteTitle',
    en: 'Quote #${quote.quoteNumber ?? ''}',
    he: 'הצעה מס׳ ${quote.quoteNumber ?? ''}',
    ar: 'عرض رقم ${quote.quoteNumber ?? ''}',
  );
  final pdfFileName = 'quote_${quote.quoteNumber ?? quote.id}.pdf';

  late final Uint8List bytes;
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }
    bytes = response.bodyBytes;
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _trOrLocale(context, l10n, 'quotePdfLoadError',
              en: 'Could not load the quote PDF.',
              he: 'לא ניתן לטעון את קובץ ההצעה.',
              ar: 'تعذر تحميل ملف العرض.'),
          style: GoogleFonts.assistant(),
        ),
        backgroundColor: AppTheme.error,
      ),
    );
    return;
  }
  if (!context.mounted) return;

  Widget roundAction({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: GoogleFonts.assistant(fontWeight: FontWeight.w700),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primary,
        backgroundColor: AppTheme.surfaceContainerLowest,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: const BorderSide(color: AppTheme.primary, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          width: 760,
          height: MediaQuery.sizeOf(ctx).height * 0.88,
          decoration: BoxDecoration(
            color: AppTheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppTheme.outlineVariant.withValues(alpha: 0.25),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 32,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.secondary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.request_quote_outlined,
                        color: AppTheme.secondary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.assistant(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: AppTheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Container(
                              height: 3,
                              width: 40,
                              decoration: BoxDecoration(
                                color: AppTheme.secondary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Material(
                      color: AppTheme.surfaceContainerHighest
                          .withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(ctx).pop(),
                        child: const SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.close_rounded,
                            color: AppTheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: AppTheme.outlineVariant.withValues(alpha: 0.25),
              ),
              Expanded(
                child: ColoredBox(
                  color: AppTheme.surfaceContainerLow,
                  child: PdfPreview(
                    build: (format) async => bytes,
                    allowPrinting: false,
                    allowSharing: false,
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    canDebug: false,
                    useActions: false,
                    pdfFileName: pdfFileName,
                    previewPageMargin: const EdgeInsets.all(18),
                    padding: const EdgeInsets.all(12),
                  ),
                ),
              ),
              Divider(
                height: 1,
                color: AppTheme.outlineVariant.withValues(alpha: 0.25),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.end,
                  children: [
                    roundAction(
                      icon: Icons.open_in_new_rounded,
                      label: _trOrLocale(context, l10n, 'openInBrowser',
                          en: 'Open', he: 'פתח', ar: 'فتح'),
                      onPressed: () async {
                        await launchUrl(
                          Uri.parse(url),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                    roundAction(
                      icon: Icons.download_rounded,
                      label: _trOrLocale(context, l10n, 'download',
                          en: 'Download', he: 'הורדה', ar: 'تنزيل'),
                      onPressed: () async {
                        await Printing.sharePdf(
                          bytes: bytes,
                          filename: pdfFileName,
                        );
                      },
                    ),
                    roundAction(
                      icon: Icons.print_rounded,
                      label: _trOrLocale(context, l10n, 'print',
                          en: 'Print', he: 'הדפס', ar: 'طباعة'),
                      onPressed: () async {
                        await Printing.layoutPdf(
                          onLayout: (format) async => bytes,
                          name: pdfFileName,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
