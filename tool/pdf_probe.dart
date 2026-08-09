// Scratch probe: renders sample strings with the pdf package to inspect
// RTL handling. Delete after use.
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<pw.Font> loadFont(String path) async {
  final bytes = await File(path).readAsBytes();
  return pw.Font.ttf(ByteData.view(bytes.buffer));
}

/// Pre-reverses LTR (Latin/digit) runs so the pdf package's RTL pass
/// restores them to their correct visual order.
String bidiCompensate(String text) {
  bool isRtlChar(int c) =>
      (c >= 0x0590 && c <= 0x08FF) ||
      (c >= 0xFB1D && c <= 0xFDFF) ||
      (c >= 0xFE70 && c <= 0xFEFF);
  bool isLtrChar(int c) =>
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      (c >= 0x30 && c <= 0x39);

  final runes = text.runes.toList();
  final n = runes.length;
  final cls = List<int>.generate(n, (i) {
    final c = runes[i];
    if (isRtlChar(c)) return -1;
    if (isLtrChar(c)) return 1;
    return 0;
  });

  final resolved = List<int>.from(cls);
  var i = 0;
  while (i < n) {
    if (resolved[i] == 0) {
      var j = i;
      while (j < n && resolved[j] == 0) {
        j++;
      }
      final before = i > 0 ? resolved[i - 1] : -1;
      final after = j < n ? cls[j] : -1;
      final v = (before == 1 && after == 1) ? 1 : -1;
      for (var k = i; k < j; k++) {
        resolved[k] = v;
      }
      i = j;
    } else {
      i++;
    }
  }

  final out = List<int>.from(runes);
  i = 0;
  while (i < n) {
    if (resolved[i] == 1) {
      var j = i;
      while (j < n && resolved[j] == 1) {
        j++;
      }
      for (var k = 0; k < j - i; k++) {
        out[i + k] = runes[j - 1 - k];
      }
      i = j;
    } else {
      i++;
    }
  }
  return String.fromCharCodes(out);
}

Future<void> main() async {
  final heb = await loadFont('assets/fonts/NotoSansHebrew-Regular.ttf');
  final latin = await loadFont('assets/fonts/NotoSans-Regular.ttf');

  pw.TextStyle st() => pw.TextStyle(
        font: heb,
        fontFallback: [latin],
        fontSize: 13,
      );

  final samples = <String>[
    'test item',
    '5354',
    '200.00 \u20aa',
    '\u20aa200.00',
    'ח.פ. 558480125',
    'טירה המשולש, 44491500, ת.ד. 3247',
    'הצעה מס׳ 00015',
    'תאריך: 08/08/2026',
    'מק״ט: 5354',
    'שם הלקוח: עומרי מוסלטאן',
    'טלפון: 050-595-2521',
    'מחיר ליחידה: 200.00 \u20aa · תוספות: כבל זהב (+50.00 \u20aa)',
    'Fixture ABC-123 גוף תאורה',
  ];

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => pw.Directionality(
        textDirection: pw.TextDirection.rtl,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            for (final s in samples) ...[
              pw.Text(
                bidiCompensate(s),
                style: st(),
                textDirection: pw.TextDirection.rtl,
                textAlign: pw.TextAlign.right,
              ),
              pw.SizedBox(height: 8),
            ],
          ],
        ),
      ),
    ),
  );

  final out = File('build/probe.pdf');
  out.parent.createSync(recursive: true);
  await out.writeAsBytes(await doc.save());
  print('wrote ${out.path}');
}
