import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/customer.dart';
import '../models/quote.dart';
import '../models/quote_item.dart';

/// Quote PDF — replica of the store's printed quote pad:
/// centred letterhead, contact strip, quote number, customer fill-in
/// lines and a plain black-grid items table (מס' / פירוט / כמות / סכום).
///
/// Important: the pdf package's RTL path runs a broken bidi pass that
/// reverses digit/Latin runs. Hebrew labels use RTL; every number, price,
/// date, phone and Latin string is drawn with an explicit LTR direction.
class QuotePdfService {
  static const _ink = PdfColor.fromInt(0xFF111111);
  static const _muted = PdfColor.fromInt(0xFF5F6364);

  // Letterhead constants, copied from the printed pad.
  static const _phoneLine = '09-7661627 | 054-6788988';
  static const _emailLine = 'Royallight2022r@gmail.com';
  static const _addressHebrew = 'טירה המשולש, ת.ד.';
  static const _addressPoBox = '3247';
  static const _businessIdLabel = 'ח.פ.';
  static const _businessIdNumber = '558480125';

  static final Map<
      String,
      ({
        pw.Font base,
        pw.Font bold,
        pw.Font fallback,
        pw.Font fallbackBold,
      })> _fontCache = {};

  static pw.MemoryImage? _logoCache;

  static Future<void> warmUp(String languageCode) async {
    final lang =
        (languageCode == 'he' || languageCode == 'ar') ? languageCode : 'en';
    await Future.wait([_loadFonts(lang), _loadLogo()]);
  }

  static Future<Uint8List> generate({
    required Customer customer,
    required Quote quote,
    required List<QuoteItem> items,
    required String languageCode,
  }) async {
    final lang =
        (languageCode == 'he' || languageCode == 'ar') ? languageCode : 'en';
    final isRtl = lang == 'he' || lang == 'ar';

    final results = await Future.wait([
      _loadLogo(),
      _loadFonts(lang),
    ]);

    final logoImage = results[0] as pw.MemoryImage?;
    final fonts = results[1] as ({
      pw.Font base,
      pw.Font bold,
      pw.Font fallback,
      pw.Font fallbackBold,
    });

    final base = fonts.base;
    final bold = fonts.bold;
    final fallback = fonts.fallback;
    final fallbackBold = fonts.fallbackBold;

    pw.TextStyle style({
      double size = 10,
      bool isBold = false,
      PdfColor color = _ink,
    }) {
      return pw.TextStyle(
        font: isBold ? bold : base,
        fontFallback: [isBold ? fallbackBold : fallback],
        fontSize: size,
        fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color,
      );
    }

    final money = NumberFormat('#,##0.00', 'en_US');
    final dateFmt = DateFormat('dd/MM/yyyy');
    final now = DateTime.now();

    // Always LTR for prices so digits never get reversed.
    String moneyText(double value) => '₪${money.format(value)}';

    final t = _labels(lang);
    final subtotal = items.fold<double>(0, (s, i) => s + i.lineTotal);
    final vat = quote.vatEnabled ? subtotal * 0.18 : 0.0;
    final grandTotal = subtotal + vat;

    final customerName = customer.customerName.trim().isNotEmpty
        ? customer.customerName
        : customer.cardName;
    final phone = customer.phones.isNotEmpty ? customer.phones.first : '';
    final address = customer.location?.trim() ?? '';
    final quoteNumberText =
        quote.quoteNumber != null ? '${quote.quoteNumber}'.padLeft(5, '0') : '—';
    final dateText = dateFmt.format(now);

    final pdf = pw.Document(
      title: '${t.docTitle} $quoteNumberText'.trim(),
      author: 'Royal Light',
    );

    const borderSide = pw.BorderSide(color: _ink, width: 0.9);
    const grid = pw.TableBorder(
      left: borderSide,
      top: borderSide,
      right: borderSide,
      bottom: borderSide,
      horizontalInside: borderSide,
      verticalInside: borderSide,
    );

    // Visual left→right columns. For RTL we reverse so מס' sits on the right.
    const tableFlex = [36.0, 310.0, 58.0, 96.0]; // מס' | פירוט | כמות | סכום
    const totalsFlex = [120.0, 130.0]; // label | amount

    Map<int, pw.TableColumnWidth> columnWidths(List<double> logicalFlex) {
      final visual = isRtl ? logicalFlex.reversed.toList() : logicalFlex;
      return {
        for (var i = 0; i < visual.length; i++)
          i: pw.FlexColumnWidth(visual[i]),
      };
    }

    List<pw.Widget> visualCells(List<pw.Widget> cells) =>
        isRtl ? cells.reversed.toList() : cells;

    /// Hebrew / Arabic label — RTL, never pass digits through here.
    pw.Widget rtlText(
      String text, {
      double size = 10,
      bool isBold = false,
      PdfColor color = _ink,
      pw.TextAlign align = pw.TextAlign.right,
      int maxLines = 4,
    }) {
      return pw.Text(
        text,
        style: style(size: size, isBold: isBold, color: color),
        textDirection: pw.TextDirection.rtl,
        textAlign: align,
        maxLines: maxLines,
        overflow: pw.TextOverflow.clip,
      );
    }

    /// Numbers, prices, dates, phones, Latin — always LTR.
    pw.Widget ltrText(
      String text, {
      double size = 10,
      bool isBold = false,
      PdfColor color = _ink,
      pw.TextAlign align = pw.TextAlign.left,
      int maxLines = 4,
    }) {
      return pw.Text(
        text,
        style: style(size: size, isBold: isBold, color: color),
        textDirection: pw.TextDirection.ltr,
        textAlign: align,
        maxLines: maxLines,
        overflow: pw.TextOverflow.clip,
      );
    }

    /// Auto-pick direction: pure digit/Latin/punctuation → LTR, else RTL.
    pw.Widget autoText(
      String text, {
      double size = 10,
      bool isBold = false,
      PdfColor color = _ink,
      pw.TextAlign? align,
      int maxLines = 4,
    }) {
      final ltr = _isPrimarilyLtr(text);
      return ltr
          ? ltrText(
              text,
              size: size,
              isBold: isBold,
              color: color,
              align: align ?? pw.TextAlign.left,
              maxLines: maxLines,
            )
          : rtlText(
              text,
              size: size,
              isBold: isBold,
              color: color,
              align: align ?? pw.TextAlign.right,
              maxLines: maxLines,
            );
    }

    pw.Widget cell(
      String text, {
      bool isBold = false,
      double size = 9.5,
      pw.TextAlign? align,
      PdfColor color = _ink,
      bool forceLtr = false,
    }) {
      final ltr = forceLtr || _isPrimarilyLtr(text);
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        child: pw.SizedBox(
          width: double.infinity,
          child: ltr
              ? ltrText(
                  text,
                  size: size,
                  isBold: isBold,
                  color: color,
                  align: align ?? pw.TextAlign.center,
                  maxLines: 3,
                )
              : rtlText(
                  text,
                  size: size,
                  isBold: isBold,
                  color: color,
                  align: align ?? pw.TextAlign.center,
                  maxLines: 3,
                ),
        ),
      );
    }

    pw.Widget detailCell(QuoteItem item) {
      final code = (item.itemNumber ?? '').trim();
      final extras = (item.extras ?? '').trim();
      final name = item.name.isEmpty ? '—' : item.name;

      final metaParts = <pw.Widget>[];
      if (code.isNotEmpty) {
        metaParts.add(
          pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: isRtl
                ? [
                    ltrText(code, size: 7.5, color: _muted),
                    rtlText(' :${t.code}', size: 7.5, color: _muted),
                  ]
                : [
                    ltrText('${t.code}: ', size: 7.5, color: _muted),
                    ltrText(code, size: 7.5, color: _muted),
                  ],
          ),
        );
      }
      if (extras.isNotEmpty) {
        metaParts.add(
          pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              if (isRtl) ...[
                if (item.extrasPrice > 0) ...[
                  ltrText(moneyText(item.extrasPrice), size: 7.5, color: _muted),
                  ltrText(' · ', size: 7.5, color: _muted),
                ],
                autoText(extras, size: 7.5, color: _muted),
                rtlText(' :${t.extras}', size: 7.5, color: _muted),
              ] else ...[
                ltrText('${t.extras}: ', size: 7.5, color: _muted),
                autoText(extras, size: 7.5, color: _muted),
                if (item.extrasPrice > 0) ...[
                  ltrText(' · ', size: 7.5, color: _muted),
                  ltrText(moneyText(item.extrasPrice), size: 7.5, color: _muted),
                ],
              ],
            ],
          ),
        );
      } else if (item.extrasPrice > 0) {
        metaParts.add(
          pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: isRtl
                ? [
                    ltrText(moneyText(item.extrasPrice), size: 7.5, color: _muted),
                    rtlText(' :${t.extras}', size: 7.5, color: _muted),
                  ]
                : [
                    ltrText('${t.extras}: ', size: 7.5, color: _muted),
                    ltrText(moneyText(item.extrasPrice), size: 7.5, color: _muted),
                  ],
          ),
        );
      }
      if (item.quantity != 1) {
        metaParts.add(
          pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: isRtl
                ? [
                    ltrText(moneyText(item.price), size: 7.5, color: _muted),
                    rtlText(' :${t.unitPrice}', size: 7.5, color: _muted),
                  ]
                : [
                    ltrText('${t.unitPrice}: ', size: 7.5, color: _muted),
                    ltrText(moneyText(item.price), size: 7.5, color: _muted),
                  ],
          ),
        );
      }

      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: pw.Column(
          crossAxisAlignment: isRtl
              ? pw.CrossAxisAlignment.end
              : pw.CrossAxisAlignment.start,
          children: [
            autoText(
              name,
              size: 9.5,
              align: isRtl ? pw.TextAlign.right : pw.TextAlign.left,
              maxLines: 3,
            ),
            if (metaParts.isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Wrap(
                spacing: 8,
                runSpacing: 2,
                alignment:
                    isRtl ? pw.WrapAlignment.end : pw.WrapAlignment.start,
                children: metaParts,
              ),
            ],
          ],
        ),
      );
    }

    pw.Widget itemsTable() {
      return pw.Table(
        border: grid,
        columnWidths: columnWidths(tableFlex),
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        children: [
          pw.TableRow(
            repeat: true,
            children: visualCells([
              cell(t.num, isBold: true, size: 9),
              cell(t.detail, isBold: true, size: 9),
              cell(t.qty, isBold: true, size: 9),
              cell(t.amount, isBold: true, size: 9),
            ]),
          ),
          for (var i = 0; i < items.length; i++)
            pw.TableRow(
              children: visualCells([
                cell('${i + 1}', size: 9, forceLtr: true),
                detailCell(items[i]),
                cell(
                  _formatQty(items[i].quantity),
                  size: 9,
                  forceLtr: true,
                ),
                cell(
                  moneyText(items[i].lineTotal),
                  size: 9,
                  forceLtr: true,
                ),
              ]),
            ),
        ],
      );
    }

    /// Label + underlined value. Numbers/phones drawn LTR; names RTL/auto.
    pw.Widget fillField(String label, String value, {bool valueLtr = false}) {
      final trimmed = value.trim();
      final valueWidget = trimmed.isEmpty
          ? pw.Text(' ', style: style(size: 10))
          : (valueLtr || _isPrimarilyLtr(trimmed))
              ? ltrText(
                  trimmed,
                  size: 10,
                  align: isRtl ? pw.TextAlign.right : pw.TextAlign.left,
                )
              : rtlText(
                  trimmed,
                  size: 10,
                  align: isRtl ? pw.TextAlign.right : pw.TextAlign.left,
                );

      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          if (isRtl) ...[
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.only(bottom: 2),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: _ink, width: 0.7),
                  ),
                ),
                child: valueWidget,
              ),
            ),
            pw.SizedBox(width: 6),
            rtlText(label, size: 10, isBold: true),
          ] else ...[
            ltrText(label, size: 10, isBold: true),
            pw.SizedBox(width: 6),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.only(bottom: 2),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: _ink, width: 0.7),
                  ),
                ),
                child: valueWidget,
              ),
            ),
          ],
        ],
      );
    }

    pw.Widget letterhead() {
      return pw.Column(
        children: [
          pw.Center(
            child: logoImage != null
                ? pw.Image(logoImage, height: 78, fit: pw.BoxFit.contain)
                : pw.Column(
                    children: [
                      ltrText('ROYAL LIGHT', size: 22, isBold: true),
                      ltrText('DESIGN & MORE', size: 9, color: _muted),
                    ],
                  ),
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: _ink, width: 0.9),
                bottom: pw.BorderSide(color: _ink, width: 0.9),
              ),
            ),
            // Forced LTR so contact pieces stay phone | email | address
            // left→right on the pad, matching the printed form.
            child: pw.Directionality(
              textDirection: pw.TextDirection.ltr,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  ltrText(_phoneLine, size: 8.5),
                  ltrText(_emailLine, size: 8.5),
                  pw.Row(
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      rtlText('$_addressHebrew ', size: 8.5),
                      ltrText(_addressPoBox, size: 8.5),
                    ],
                  ),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                ltrText(_businessIdNumber, size: 8.5),
                pw.SizedBox(width: 4),
                rtlText(_businessIdLabel, size: 8.5),
              ],
            ),
          ),
        ],
      );
    }

    pw.TableRow totalsRow(
      String label, {
      String? labelLtrSuffix,
      required String value,
      bool isBold = false,
    }) {
      final size = isBold ? 10.0 : 9.5;
      final labelChild = labelLtrSuffix == null
          ? (isRtl
              ? rtlText(label, size: size, isBold: isBold, align: pw.TextAlign.right)
              : ltrText(label, size: size, isBold: isBold, align: pw.TextAlign.left))
          : pw.Row(
              mainAxisAlignment: isRtl
                  ? pw.MainAxisAlignment.end
                  : pw.MainAxisAlignment.start,
              children: isRtl
                  ? [
                      ltrText(labelLtrSuffix, size: size, isBold: isBold),
                      pw.SizedBox(width: 3),
                      rtlText(label, size: size, isBold: isBold),
                    ]
                  : [
                      ltrText(label, size: size, isBold: isBold),
                      pw.SizedBox(width: 3),
                      ltrText(labelLtrSuffix, size: size, isBold: isBold),
                    ],
            );
      return pw.TableRow(
        children: visualCells([
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
            child: labelChild,
          ),
          cell(value, isBold: isBold, size: size, forceLtr: true),
        ]),
      );
    }

    // Page stays LTR so Rows/Tables aren't mirrored by the pdf package.
    // RTL is applied only on individual Hebrew Text widgets.
    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.ltr,
          margin: const pw.EdgeInsets.fromLTRB(32, 26, 32, 26),
          theme: pw.ThemeData.withFont(base: base, bold: bold),
        ),
        header: (context) {
          if (context.pageNumber == 1) {
            return pw.SizedBox();
          }
          return pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  ltrText(
                    '${context.pageNumber}/${context.pagesCount}',
                    size: 8,
                    color: _muted,
                  ),
                  pw.Row(
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      ltrText(quoteNumberText, size: 9, isBold: true, color: _muted),
                      pw.SizedBox(width: 4),
                      rtlText(t.quoteNo, size: 9, isBold: true, color: _muted),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
            ],
          );
        },
        footer: (context) {
          return pw.Center(
            child: ltrText(
              '${context.pageNumber}/${context.pagesCount}',
              size: 8,
              color: _muted,
              align: pw.TextAlign.center,
            ),
          );
        },
        build: (context) {
          final widgets = <pw.Widget>[
            letterhead(),
            pw.SizedBox(height: 14),

            // Quote number (right) + date (left), matching the pad.
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    ltrText(dateText, size: 10),
                    pw.SizedBox(width: 4),
                    rtlText('${t.date}:', size: 10),
                  ],
                ),
                pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    ltrText(quoteNumberText, size: 14, isBold: true),
                    pw.SizedBox(width: 6),
                    rtlText(t.quoteNo, size: 14, isBold: true),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),

            fillField(t.customerName, customerName),
            pw.SizedBox(height: 8),
            pw.Row(
              children: [
                pw.Expanded(
                  child: fillField(t.phone, phone, valueLtr: true),
                ),
                pw.SizedBox(width: 18),
                pw.Expanded(child: fillField(t.address, address)),
              ],
            ),
            pw.SizedBox(height: 14),

            itemsTable(),
            pw.SizedBox(height: 12),

            // Totals under the amount column (left side of the pad).
            pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: pw.SizedBox(
                width: 250,
                child: pw.Table(
                  border: grid,
                  columnWidths: columnWidths(totalsFlex),
                  children: quote.vatEnabled
                      ? [
                          totalsRow(t.subtotal, value: moneyText(subtotal)),
                          totalsRow(
                            t.vat,
                            labelLtrSuffix: '18%',
                            value: moneyText(vat),
                          ),
                          totalsRow(
                            t.totalIncVat,
                            value: moneyText(grandTotal),
                            isBold: true,
                          ),
                        ]
                      : [
                          totalsRow(
                            t.subtotal,
                            value: moneyText(grandTotal),
                            isBold: true,
                          ),
                        ],
                ),
              ),
            ),
          ];

          if (quote.notes != null && quote.notes!.trim().isNotEmpty) {
            widgets.add(pw.SizedBox(height: 12));
            widgets.add(
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _ink, width: 0.9),
                ),
                child: pw.Column(
                  crossAxisAlignment: isRtl
                      ? pw.CrossAxisAlignment.end
                      : pw.CrossAxisAlignment.start,
                  children: [
                    rtlText(t.notes, size: 9, isBold: true),
                    pw.SizedBox(height: 3),
                    autoText(
                      quote.notes!.trim(),
                      size: 9.5,
                      align: isRtl ? pw.TextAlign.right : pw.TextAlign.left,
                    ),
                  ],
                ),
              ),
            );
          }

          return widgets;
        },
      ),
    );

    return pdf.save();
  }

  /// True when the string has no RTL letters (safe to draw LTR).
  static bool _isPrimarilyLtr(String text) {
    for (final c in text.runes) {
      if ((c >= 0x0590 && c <= 0x08FF) ||
          (c >= 0xFB1D && c <= 0xFDFF) ||
          (c >= 0xFE70 && c <= 0xFEFF)) {
        return false;
      }
    }
    return text.trim().isNotEmpty;
  }

  static Future<pw.MemoryImage?> _loadLogo() async {
    if (_logoCache != null) return _logoCache;
    try {
      final data = await rootBundle.load('assets/branding/logo.png');
      if (data.lengthInBytes == 0) return null;
      _logoCache = pw.MemoryImage(data.buffer.asUint8List());
      return _logoCache;
    } catch (_) {
      return null;
    }
  }

  static Future<pw.Font> _fontFromAsset(String path) async {
    final data = await rootBundle.load(path);
    if (data.lengthInBytes == 0) {
      throw StateError('Font asset is empty: $path');
    }
    return pw.Font.ttf(data);
  }

  static Future<
      ({
        pw.Font base,
        pw.Font bold,
        pw.Font fallback,
        pw.Font fallbackBold,
      })> _loadFontsFromAssets(String lang) async {
    final latinRegular =
        await _fontFromAsset('assets/fonts/NotoSans-Regular.ttf');
    final latinBold = await _fontFromAsset('assets/fonts/NotoSans-Bold.ttf');

    if (lang == 'ar') {
      return (
        base: await _fontFromAsset('assets/fonts/NotoSansArabic-Regular.ttf'),
        bold: await _fontFromAsset('assets/fonts/NotoSansArabic-Bold.ttf'),
        fallback: latinRegular,
        fallbackBold: latinBold,
      );
    }

    if (lang == 'he') {
      return (
        base: await _fontFromAsset('assets/fonts/NotoSansHebrew-Regular.ttf'),
        bold: await _fontFromAsset('assets/fonts/NotoSansHebrew-Bold.ttf'),
        fallback: latinRegular,
        fallbackBold: latinBold,
      );
    }

    return (
      base: latinRegular,
      bold: latinBold,
      fallback: latinRegular,
      fallbackBold: latinBold,
    );
  }

  static Future<
      ({
        pw.Font base,
        pw.Font bold,
        pw.Font fallback,
        pw.Font fallbackBold,
      })> _loadFontsFromGoogle(String lang) async {
    final latinRegular = await PdfGoogleFonts.notoSansRegular();
    final latinBold = await PdfGoogleFonts.notoSansBold();

    if (lang == 'ar') {
      return (
        base: await PdfGoogleFonts.notoSansArabicRegular(),
        bold: await PdfGoogleFonts.notoSansArabicBold(),
        fallback: latinRegular,
        fallbackBold: latinBold,
      );
    }

    if (lang == 'he') {
      return (
        base: await PdfGoogleFonts.notoSansHebrewRegular(),
        bold: await PdfGoogleFonts.notoSansHebrewBold(),
        fallback: latinRegular,
        fallbackBold: latinBold,
      );
    }

    return (
      base: latinRegular,
      bold: latinBold,
      fallback: latinRegular,
      fallbackBold: latinBold,
    );
  }

  static Future<
      ({
        pw.Font base,
        pw.Font bold,
        pw.Font fallback,
        pw.Font fallbackBold,
      })> _loadFonts(String lang) async {
    final cached = _fontCache[lang];
    if (cached != null) return cached;
    try {
      final fonts = await _loadFontsFromAssets(lang);
      _fontCache[lang] = fonts;
      return fonts;
    } catch (_) {
      final fonts = await _loadFontsFromGoogle(lang);
      _fontCache[lang] = fonts;
      return fonts;
    }
  }

  static String _formatQty(double q) {
    if (q == q.roundToDouble()) return q.toInt().toString();
    var s = q.toStringAsFixed(3);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  static ({
    String docTitle,
    String quoteNo,
    String date,
    String customerName,
    String phone,
    String address,
    String num,
    String detail,
    String qty,
    String amount,
    String subtotal,
    String vat,
    String totalIncVat,
    String notes,
    String code,
    String extras,
    String unitPrice,
  }) _labels(String lang) {
    return switch (lang) {
      'he' => (
          docTitle: 'הצעת מחיר',
          quoteNo: 'הצעה מס׳',
          date: 'תאריך',
          customerName: 'שם הלקוח',
          phone: 'טלפון',
          address: 'כתובת',
          num: 'מס׳',
          detail: 'פירוט',
          qty: 'כמות',
          amount: 'סכום',
          subtotal: 'סה״כ',
          vat: 'מע״מ',
          totalIncVat: 'סה״כ כולל מע״מ',
          notes: 'הערות',
          code: 'מק״ט',
          extras: 'תוספות',
          unitPrice: 'מחיר ליחידה',
        ),
      'ar' => (
          docTitle: 'عرض سعر',
          quoteNo: 'عرض رقم',
          date: 'التاريخ',
          customerName: 'اسم العميل',
          phone: 'الهاتف',
          address: 'العنوان',
          num: 'رقم',
          detail: 'التفاصيل',
          qty: 'الكمية',
          amount: 'المبلغ',
          subtotal: 'المجموع',
          vat: 'ض.ق.م',
          totalIncVat: 'المجموع شامل الضريبة',
          notes: 'ملاحظات',
          code: 'الرمز',
          extras: 'إضافات',
          unitPrice: 'سعر الوحدة',
        ),
      _ => (
          docTitle: 'Price Quote',
          quoteNo: 'Quote No.',
          date: 'Date',
          customerName: 'Customer',
          phone: 'Phone',
          address: 'Address',
          num: 'No.',
          detail: 'Description',
          qty: 'Qty',
          amount: 'Amount',
          subtotal: 'Total',
          vat: 'VAT',
          totalIncVat: 'Total incl. VAT',
          notes: 'Notes',
          code: 'Code',
          extras: 'Extras',
          unitPrice: 'Unit price',
        ),
    };
  }
}
