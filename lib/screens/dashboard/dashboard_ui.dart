import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';

/// Shared chrome + helpers for the dashboard cards.

// ─────────────────────────────────────────────────────────────────
// Localization
// ─────────────────────────────────────────────────────────────────

/// ARB lookup with a per-locale literal fallback.
///
/// Same contract as the `_tr` / `_trOrLocale` helpers each screen defines
/// privately; shared here because the dashboard now spans several files.
/// `AppLocalizations.tr` returns the key itself on a miss, so that counts as
/// missing and we fall through to the literal for the active language.
String dashTr(
  BuildContext context,
  AppLocalizations? l10n,
  String key, {
  required String en,
  required String he,
  required String ar,
}) {
  final v = l10n?.tr(key);
  if (v != null && v.isNotEmpty && v != key) return v;
  return switch (Localizations.localeOf(context).languageCode) {
    'he' => he,
    'ar' => ar,
    _ => en,
  };
}

// ─────────────────────────────────────────────────────────────────
// Formatting
// ─────────────────────────────────────────────────────────────────

final _currency = NumberFormat.currency(symbol: '₪', decimalDigits: 0);
final _compactCurrency = NumberFormat.compactCurrency(symbol: '₪', decimalDigits: 0);
final _decimal = NumberFormat.decimalPattern();

/// `₪1,250` — the single place the shekel symbol is written.
String money(num value) => _currency.format(value);

/// `₪12K` for tight spots like chart axes and pill badges.
String moneyCompact(num value) => _compactCurrency.format(value);

String count(num value) => _decimal.format(value);

// ─────────────────────────────────────────────────────────────────
// Card chrome
// ─────────────────────────────────────────────────────────────────

const double kCardRadius = 20;

BoxDecoration dashCardDecoration({Color? accent, bool emphasized = false}) {
  return BoxDecoration(
    color: AppTheme.surfaceContainerLowest,
    borderRadius: BorderRadius.circular(kCardRadius),
    border: Border.all(
      color: accent != null
          ? accent.withValues(alpha: 0.20)
          : AppTheme.outlineVariant.withValues(alpha: 0.4),
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: emphasized ? 0.06 : 0.04),
        blurRadius: emphasized ? 24 : 16,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

/// Rounded tinted square holding a card's icon.
class DashIconChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const DashIconChip({
    super.key,
    required this.icon,
    required this.color,
    this.size = 38,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(size * 0.32),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }
}

/// Card header: icon chip, title, optional subtitle, optional trailing widget.
class DashCardHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const DashCardHeader({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DashIconChip(icon: icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: GoogleFonts.assistant(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: GoogleFonts.assistant(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Small pill badge — counts, percentages, status words.
class DashPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const DashPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: GoogleFonts.assistant(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder shown while a card's data is still loading, sized so the
/// layout doesn't jump when the real value lands.
class DashValueSkeleton extends StatelessWidget {
  final double width;
  final double height;

  const DashValueSkeleton({super.key, this.width = 64, this.height = 28});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

/// Empty-state block for cards with nothing to show.
class DashEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const DashEmptyState({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 26, color: AppTheme.outlineVariant),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.assistant(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
