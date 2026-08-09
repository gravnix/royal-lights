// Scratch probe for the pdf package's RTL pipeline. Delete after use.
// ignore_for_file: avoid_print
import 'package:bidi/bidi.dart' as bidi;

String logicalToVisual(String input) {
  final buffer = StringBuffer();
  final paragraphs = bidi.BidiString.fromLogical(input).paragraphs;
  for (final paragraph in paragraphs) {
    final endsWithNewLine = paragraph.separator == 10;
    final endIndex = paragraph.bidiText.length - (endsWithNewLine ? 1 : 0);
    final visual = String.fromCharCodes(paragraph.bidiText, 0, endIndex);
    buffer.write(visual.split(' ').reversed.join(' '));
    if (endsWithNewLine) {
      buffer.writeln();
    }
  }
  return buffer.toString();
}

// Simulates RichText: split into words, lay LTR, mirror for RTL.
// Final left-to-right reading = word order reversed back.
String rendered(String input) {
  final visual = logicalToVisual(input);
  return visual.split(' ').reversed.join(' ');
}

void main() {
  final samples = [
    'test item',
    '5354',
    '200.00 \u20aa',
    '\u20aa200.00',
    'ח.פ. 558480125',
    'טירה המשולש, 44491500, ת.ד. 3247',
    'הצעה מס׳ 00015',
    'תאריך: 08/08/2026',
    'מק״ט: 5354',
    '09-7661627 | 054-6788988',
    'שם הלקוח',
  ];
  for (final s in samples) {
    print('IN : $s');
    print('VIS: ${logicalToVisual(s)}');
    print('OUT: ${rendered(s)}');
    print('---');
  }
}
