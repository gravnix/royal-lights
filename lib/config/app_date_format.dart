import 'package:intl/intl.dart';

/// Standard date display for tables, filters, and tabular list rows.
abstract final class AppDateFormat {
  static final DateFormat _table = DateFormat('dd-MM-yyyy');

  /// Formats [date] as `DD-MM-YYYY` (e.g. `20-05-2026`).
  static String table(DateTime date) => _table.format(date);

  /// Table cell: `-` when [date] is null.
  static String tableOrDash(DateTime? date) =>
      date == null ? '-' : table(date);

  /// Inline field: empty string when [date] is null.
  static String tableOrEmpty(DateTime? date) =>
      date == null ? '' : table(date);
}
