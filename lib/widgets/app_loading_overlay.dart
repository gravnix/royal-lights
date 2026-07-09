import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';

class AppLoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;
  final String? label;

  const AppLoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = label ?? l10n?.tr('loading') ?? 'טוען…';

    return Stack(
      children: [
        child,
        if (isLoading)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.black.withValues(alpha: 0.04),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.outlineVariant.withValues(alpha: 0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        text,
                        style: GoogleFonts.assistant(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
