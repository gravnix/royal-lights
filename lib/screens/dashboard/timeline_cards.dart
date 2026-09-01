import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
// intl also exports a TextDirection; hide it so Directionality's (dart:ui) wins.
import 'package:intl/intl.dart' hide TextDirection;

import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/timeline_note.dart';
import 'dashboard_metrics.dart';
import 'dashboard_ui.dart';
import 'timeline_note_dialog.dart';

/// Opens the add/edit dialog for a reminder.
Future<void> showTimelineNoteDialog(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations? l10n, {
  required DateTime date,
  TimelineNote? existing,
}) {
  return showDialog(
    context: context,
    builder: (_) => TimelineNoteDialog(
      ref: ref,
      l10n: l10n,
      initialDate: date,
      existingNote: existing,
    ),
  );
}

List<TimelineNote> _notesOn(List<TimelineNote> notes, DateTime day) {
  final target = dateOnly(day);
  final result =
      notes.where((n) => dateOnly(n.noteDate) == target).toList();
  result.sort((a, b) => a.title.compareTo(b.title));
  return result;
}

// ─────────────────────────────────────────────────────────────────
// Alerts panel — today + tomorrow
// ─────────────────────────────────────────────────────────────────

/// Surfaces reminders on their date and the day before, which is the alerting
/// behaviour the app promises. Anything further out lives only in the calendar.
class RemindersCard extends StatelessWidget {
  final List<TimelineNote> notes;
  final bool loading;
  final AppLocalizations? l10n;
  final WidgetRef ref;

  const RemindersCard({
    super.key,
    required this.notes,
    required this.loading,
    required this.l10n,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = dateOnly(now);
    final tomorrow = today.add(const Duration(days: 1));

    final todayNotes = _notesOn(notes, today);
    final tomorrowNotes = _notesOn(notes, tomorrow);
    final total = todayNotes.length + tomorrowNotes.length;

    return Container(
      // Leads the dashboard alongside the calendar, so it always reads as a
      // primary card rather than only when something is due.
      padding: const EdgeInsets.all(20),
      decoration: dashCardDecoration(
        accent: AppTheme.secondary,
        emphasized: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashCardHeader(
            icon: Icons.notifications_active_rounded,
            color: AppTheme.secondary,
            title: dashTr(context, l10n, 'reminders',
                en: 'Reminders', he: 'תזכורות', ar: 'التذكيرات'),
            subtitle: dashTr(context, l10n, 'remindersSubtitle',
                en: 'Today and tomorrow',
                he: 'להיום ולמחר',
                ar: 'اليوم وغدًا'),
            trailing: total > 0
                ? DashPill(label: '$total', color: AppTheme.secondary)
                : null,
          ),
          const SizedBox(height: 16),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (total == 0)
            DashEmptyState(
              icon: Icons.notifications_none_rounded,
              message: dashTr(context, l10n, 'noReminders',
                  en: 'No reminders for today or tomorrow',
                  he: 'אין תזכורות להיום או למחר',
                  ar: 'لا توجد تذكيرات لليوم أو غدًا'),
            )
          else ...[
            if (todayNotes.isNotEmpty)
              _ReminderGroup(
                label: dashTr(context, l10n, 'remindersToday',
                    en: 'Today', he: 'היום', ar: 'اليوم'),
                color: AppTheme.secondary,
                notes: todayNotes,
                l10n: l10n,
                ref: ref,
              ),
            if (todayNotes.isNotEmpty && tomorrowNotes.isNotEmpty)
              const SizedBox(height: 14),
            if (tomorrowNotes.isNotEmpty)
              _ReminderGroup(
                label: dashTr(context, l10n, 'remindersTomorrow',
                    en: 'Tomorrow', he: 'מחר', ar: 'غدًا'),
                color: AppTheme.onSurfaceVariant,
                notes: tomorrowNotes,
                l10n: l10n,
                ref: ref,
              ),
          ],
          const SizedBox(height: 14),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => showTimelineNoteDialog(
                context,
                ref,
                l10n,
                date: today,
              ),
              icon: const Icon(Icons.add_rounded,
                  size: 18, color: AppTheme.secondary),
              label: Text(
                dashTr(context, l10n, 'addReminder',
                    en: 'New reminder',
                    he: 'תזכורת חדשה',
                    ar: 'تذكير جديد'),
                style: GoogleFonts.assistant(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.secondary,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderGroup extends StatelessWidget {
  final String label;
  final Color color;
  final List<TimelineNote> notes;
  final AppLocalizations? l10n;
  final WidgetRef ref;

  const _ReminderGroup({
    required this.label,
    required this.color,
    required this.notes,
    required this.l10n,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.assistant(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: color,
          ),
        ),
        const SizedBox(height: 8),
        for (final note in notes) ...[
          _ReminderRow(note: note, color: color, l10n: l10n, ref: ref),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _ReminderRow extends StatelessWidget {
  final TimelineNote note;
  final Color color;
  final AppLocalizations? l10n;
  final WidgetRef ref;

  const _ReminderRow({
    required this.note,
    required this.color,
    required this.l10n,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showTimelineNoteDialog(
        context,
        ref,
        l10n,
        date: note.noteDate,
        existing: note,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsetsDirectional.only(top: 6, end: 10),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title,
                    style: GoogleFonts.assistant(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ((note.body ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      note.body!,
                      style: GoogleFonts.assistant(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Month calendar
// ─────────────────────────────────────────────────────────────────

/// Inline month grid. Sunday-first (the Israeli week), dots on days that carry
/// reminders, today ringed in gold. Tapping a day opens that day's notes.
class CalendarCard extends StatefulWidget {
  final List<TimelineNote> notes;
  final bool loading;
  final AppLocalizations? l10n;
  final WidgetRef ref;

  const CalendarCard({
    super.key,
    required this.notes,
    required this.loading,
    required this.l10n,
    required this.ref,
  });

  @override
  State<CalendarCard> createState() => _CalendarCardState();
}

class _CalendarCardState extends State<CalendarCard> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final localeName = Localizations.localeOf(context).toString();
    final today = dateOnly(DateTime.now());

    // Sunday-first columns: weekday 7 (Sun) → 0 … 6 (Sat) → 6.
    final leadingBlanks = _month.weekday % 7;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;

    // Any Sunday works as the seed for locale-aware weekday initials.
    final weekdaySeed = DateTime(2024, 1, 7);
    final weekdayLabels = List.generate(
      7,
      (i) => DateFormat.E(localeName)
          .format(weekdaySeed.add(Duration(days: i))),
    );

    final noteDays = <DateTime>{
      for (final n in widget.notes) dateOnly(n.noteDate),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: dashCardDecoration(
        accent: AppTheme.secondary,
        emphasized: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashCardHeader(
            icon: Icons.calendar_month_rounded,
            color: AppTheme.primary,
            title: dashTr(context, l10n, 'calendar',
                en: 'Calendar', he: 'לוח שנה', ar: 'التقويم'),
            subtitle: dashTr(context, l10n, 'calendarSubtitle',
                en: 'Pick a day to add a reminder',
                he: 'בחר יום כדי להוסיף תזכורת',
                ar: 'اختر يومًا لإضافة تذكير'),
          ),
          const SizedBox(height: 16),

          // ── Month switcher ────────────────────────────────────────
          Row(
            children: [
              _MonthArrow(
                icon: Icons.chevron_right_rounded,
                onTap: () => _shiftMonth(-1),
                semanticLabel: dashTr(context, l10n, 'previousMonth',
                    en: 'Previous month',
                    he: 'חודש קודם',
                    ar: 'الشهر السابق'),
                flipForLtr: true,
              ),
              Expanded(
                child: Text(
                  DateFormat('MMMM y', localeName).format(_month),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.assistant(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.onSurface,
                  ),
                ),
              ),
              _MonthArrow(
                icon: Icons.chevron_left_rounded,
                onTap: () => _shiftMonth(1),
                semanticLabel: dashTr(context, l10n, 'nextMonth',
                    en: 'Next month', he: 'חודש הבא', ar: 'الشهر التالي'),
                flipForLtr: true,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Weekday header ────────────────────────────────────────
          Row(
            children: [
              for (final label in weekdayLabels)
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.assistant(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      color: AppTheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),

          // ── Day grid ──────────────────────────────────────────────
          // Plain Rows rather than a shrink-wrapped GridView: this card sits
          // inside an IntrinsicHeight row, and a lazy viewport cannot report
          // intrinsic dimensions (it throws outright).
          Column(
            children: [
              for (var week = 0;
                  week < ((leadingBlanks + daysInMonth) / 7).ceil();
                  week++) ...[
                if (week > 0) const SizedBox(height: 4),
                SizedBox(
                  height: 38,
                  child: Row(
                    children: [
                      for (var col = 0; col < 7; col++) ...[
                        if (col > 0) const SizedBox(width: 4),
                        Expanded(
                          child: Builder(builder: (context) {
                            final dayNumber =
                                week * 7 + col - leadingBlanks + 1;
                            if (dayNumber < 1 || dayNumber > daysInMonth) {
                              return const SizedBox.shrink();
                            }
                            final day = DateTime(
                                _month.year, _month.month, dayNumber);
                            return _DayCell(
                              day: day,
                              isToday: day == today,
                              hasNotes: noteDays.contains(day),
                              onTap: () => _openDay(day),
                            );
                          }),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openDay(DateTime day) async {
    final dayNotes = _notesOn(widget.notes, day);
    if (dayNotes.isEmpty) {
      await showTimelineNoteDialog(context, widget.ref, widget.l10n,
          date: day);
      return;
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => _DayNotesDialog(
        day: day,
        notes: dayNotes,
        l10n: widget.l10n,
        ref: widget.ref,
      ),
    );
  }
}

class _MonthArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;

  /// The chevrons read as back/forward, so they mirror with the text direction.
  final bool flipForLtr;

  const _MonthArrow({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.flipForLtr = false,
  });

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final effectiveIcon = !flipForLtr || isRtl
        ? icon
        : (icon == Icons.chevron_right_rounded
            ? Icons.chevron_left_rounded
            : Icons.chevron_right_rounded);

    return IconButton(
      onPressed: onTap,
      icon: Icon(effectiveIcon, size: 20),
      tooltip: semanticLabel,
      color: AppTheme.onSurfaceVariant,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool isToday;
  final bool hasNotes;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.isToday,
    required this.hasNotes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    if (isToday) {
      background = AppTheme.secondary.withValues(alpha: 0.14);
      foreground = AppTheme.secondary;
    } else if (hasNotes) {
      background = AppTheme.surfaceContainerHighest.withValues(alpha: 0.45);
      foreground = AppTheme.onSurface;
    } else {
      background = Colors.transparent;
      foreground = AppTheme.onSurfaceVariant;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          border: isToday
              ? Border.all(
                  color: AppTheme.secondary.withValues(alpha: 0.55),
                  width: 1.5,
                )
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: GoogleFonts.assistant(
                fontSize: 12.5,
                fontWeight:
                    isToday || hasNotes ? FontWeight.w800 : FontWeight.w600,
                color: foreground,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: hasNotes ? AppTheme.secondary : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lists the reminders on one day, with a shortcut to add another.
class _DayNotesDialog extends StatelessWidget {
  final DateTime day;
  final List<TimelineNote> notes;
  final AppLocalizations? l10n;
  final WidgetRef ref;

  const _DayNotesDialog({
    required this.day,
    required this.notes,
    required this.l10n,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final localeName = Localizations.localeOf(context).toString();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: AppTheme.surfaceContainerLowest,
      elevation: 8,
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('EEEE, d MMMM y', localeName).format(day),
              style: GoogleFonts.assistant(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppTheme.onSurface,
              ),
            ),
            const SizedBox(height: 20),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final note in notes) ...[
                      _ReminderRow(
                        note: note,
                        color: AppTheme.secondary,
                        l10n: l10n,
                        ref: ref,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    showTimelineNoteDialog(context, ref, l10n, date: day);
                  },
                  icon: const Icon(Icons.add_rounded,
                      size: 18, color: AppTheme.secondary),
                  label: Text(
                    dashTr(context, l10n, 'addReminder',
                        en: 'New reminder',
                        he: 'תזכורת חדשה',
                        ar: 'تذكير جديد'),
                    style: GoogleFonts.assistant(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.secondary,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    dashTr(context, l10n, 'close',
                        en: 'Close', he: 'סגור', ar: 'إغلاق'),
                    style: GoogleFonts.assistant(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
