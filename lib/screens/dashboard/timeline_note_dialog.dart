import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_date_format.dart';
import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/timeline_note.dart';
import '../../providers/providers.dart';
import 'dashboard_ui.dart';

/// Add / edit / delete a dated reminder.
///
/// Follows the `InventoryItemDialog` shape: a StatefulWidget holding the
/// WidgetRef, imperative validation with an early return, `_saving` gating the
/// save button, then invalidate-and-pop.
class TimelineNoteDialog extends StatefulWidget {
  final WidgetRef ref;
  final AppLocalizations? l10n;

  /// Pre-selected date for a new note — the day the user tapped in the calendar.
  final DateTime initialDate;

  /// When non-null the dialog edits this note instead of creating one.
  final TimelineNote? existingNote;

  const TimelineNoteDialog({
    super.key,
    required this.ref,
    required this.l10n,
    required this.initialDate,
    this.existingNote,
  });

  @override
  State<TimelineNoteDialog> createState() => _TimelineNoteDialogState();
}

class _TimelineNoteDialogState extends State<TimelineNoteDialog> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  late DateTime _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingNote;
    if (existing != null) {
      _titleCtrl.text = existing.title;
      _bodyCtrl.text = existing.body ?? '';
      _date = existing.noteDate;
    } else {
      _date = widget.initialDate;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 2, 1, 1);
    final last = DateTime(now.year + 5, 12, 31);
    // showDatePicker asserts when initialDate falls outside the bounds.
    var initial = _date;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;

    final picked = await showDatePicker(
      context: context,
      locale: Localizations.localeOf(context),
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: dashTr(context, widget.l10n, 'selectDate',
          en: 'Select date', he: 'בחר תאריך', ar: 'اختر التاريخ'),
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  Future<void> _save() async {
    final l10n = widget.l10n;
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(dashTr(context, l10n, 'reminderTitleRequired',
              en: 'Please enter a reminder title',
              he: 'נא להזין כותרת לתזכורת',
              ar: 'يرجى إدخال عنوان للتذكير')),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final username = widget.ref.read(currentUsernameProvider);
      final service = widget.ref.read(timelineNoteServiceProvider);
      final existing = widget.existingNote;

      if (existing == null) {
        await service.create(TimelineNote(
          id: '',
          noteDate: _date,
          title: title,
          body: body.isEmpty ? null : body,
          createdBy: username,
          updatedBy: username,
        ));
      } else {
        await service.update(existing.id, {
          'note_date': _date.toIso8601String().split('T').first,
          'title': title,
          'body': body.isEmpty ? null : body,
          'updated_by': username,
        });
      }

      widget.ref.invalidate(timelineNotesProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n?.tr('error') ?? 'Error'}: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final l10n = widget.l10n;
    final existing = widget.existingNote;
    if (existing == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          dashTr(context, l10n, 'deleteReminder',
              en: 'Delete reminder?',
              he: 'למחוק את התזכורת?',
              ar: 'حذف التذكير؟'),
          style: GoogleFonts.assistant(fontWeight: FontWeight.w800),
        ),
        content: Text(
          existing.title,
          style: GoogleFonts.assistant(color: AppTheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n?.tr('cancel') ?? 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n?.tr('delete') ?? 'Delete',
              style: const TextStyle(color: AppTheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await widget.ref.read(timelineNoteServiceProvider).delete(existing.id);
      widget.ref.invalidate(timelineNotesProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n?.tr('error') ?? 'Error'}: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final isEdit = widget.existingNote != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: AppTheme.surfaceContainerLowest,
      elevation: 8,
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEdit
                    ? dashTr(context, l10n, 'editReminder',
                        en: 'Edit reminder',
                        he: 'עריכת תזכורת',
                        ar: 'تعديل التذكير')
                    : dashTr(context, l10n, 'addReminder',
                        en: 'New reminder',
                        he: 'תזכורת חדשה',
                        ar: 'تذكير جديد'),
                style: GoogleFonts.assistant(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.onSurface,
                ),
              ),
              const SizedBox(height: 24),

              // ── Date ────────────────────────────────────────────────
              InkWell(
                onTap: _saving ? null : _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.secondary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.secondary.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event_rounded,
                          size: 20, color: AppTheme.secondary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dashTr(context, l10n, 'reminderDate',
                                  en: 'Reminder date',
                                  he: 'תאריך התזכורת',
                                  ar: 'تاريخ التذكير'),
                              style: GoogleFonts.assistant(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: AppTheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              AppDateFormat.table(_date),
                              style: GoogleFonts.assistant(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.edit_calendar_rounded,
                          size: 18, color: AppTheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Title ───────────────────────────────────────────────
              TextField(
                controller: _titleCtrl,
                autofocus: true,
                textInputAction: TextInputAction.next,
                style: GoogleFonts.assistant(color: AppTheme.onSurface),
                decoration: InputDecoration(
                  labelText: dashTr(context, l10n, 'reminderTitle',
                      en: 'Title', he: 'כותרת', ar: 'العنوان'),
                  labelStyle:
                      const TextStyle(color: AppTheme.onSurfaceVariant),
                  prefixIcon: const Icon(Icons.notifications_active_outlined,
                      color: AppTheme.onSurfaceVariant),
                  filled: true,
                  fillColor:
                      AppTheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Body ────────────────────────────────────────────────
              TextField(
                controller: _bodyCtrl,
                maxLines: 3,
                style: GoogleFonts.assistant(color: AppTheme.onSurface),
                decoration: InputDecoration(
                  labelText: dashTr(context, l10n, 'reminderNote',
                      en: 'Note (optional)',
                      he: 'הערה (רשות)',
                      ar: 'ملاحظة (اختياري)'),
                  labelStyle:
                      const TextStyle(color: AppTheme.onSurfaceVariant),
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor:
                      AppTheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // ── Actions ─────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isEdit)
                    TextButton.icon(
                      onPressed: _saving ? null : _delete,
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 18, color: AppTheme.error),
                      label: Text(
                        l10n?.tr('delete') ?? 'Delete',
                        style: GoogleFonts.assistant(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.error,
                        ),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      l10n?.tr('cancel') ?? 'Cancel',
                      style: GoogleFonts.assistant(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.secondary,
                      foregroundColor: AppTheme.onSecondary,
                      elevation: 0,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.onSecondary,
                            ),
                          )
                        : Text(
                            l10n?.tr('save') ?? 'Save',
                            style: GoogleFonts.assistant(
                                fontWeight: FontWeight.w700),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
