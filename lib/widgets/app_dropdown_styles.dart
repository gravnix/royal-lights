import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_theme.dart';

/// [DropdownMenu.decorationBuilder] with an animated chevron and the same
/// fields as the default decoration. Do not use with [DropdownMenu.enableFilter]
/// — the trailing control must stay the framework default so open/reset logic runs.
DropdownMenuDecorationBuilder animatedDropdownDecorationBuilder({
  Widget? label,
  String? hintText,
  String? helperText,
  String? errorText,
  Widget? leadingIcon,
  bool enabled = true,
  FocusNode? trailingIconFocusNode,
  double iconSize = 22,
  Color? iconColor,
}) {
  final chevronColor = iconColor ?? AppTheme.secondary;
  return (BuildContext context, MenuController controller) {
    return InputDecoration(
      label: label,
      hintText: hintText,
      helperText: helperText,
      errorText: errorText,
      prefixIcon: leadingIcon,
      suffixIcon: _AnimatedDropdownSuffix(
        controller: controller,
        enabled: enabled,
        focusNode: trailingIconFocusNode,
        iconSize: iconSize,
        iconColor: chevronColor,
      ),
    );
  };
}

class _AnimatedDropdownSuffix extends StatelessWidget {
  const _AnimatedDropdownSuffix({
    required this.controller,
    required this.enabled,
    this.focusNode,
    required this.iconSize,
    required this.iconColor,
  });

  final MenuController controller;
  final bool enabled;
  final FocusNode? focusNode;
  final double iconSize;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final isOpen = MenuController.maybeIsOpenOf(context) ?? false;
    final effectiveColor =
        enabled ? iconColor : iconColor.withValues(alpha: 0.38);

    return Padding(
      padding: const EdgeInsets.all(4),
      child: AnimatedRotation(
        turns: isOpen ? 0.5 : 0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        child: IconButton(
          focusNode: focusNode,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: iconSize,
            color: effectiveColor,
          ),
          onPressed: enabled
              ? () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                }
              : null,
        ),
      ),
    );
  }
}

/// Prevents [DropdownMenu] anchor `leadingIcon` widgets from expanding (fixes
/// oversized dots/icons in the closed field).
Widget dropdownLeadingSlot(Widget child) {
  return SizedBox(
    width: 22,
    height: 22,
    child: Center(child: child),
  );
}

/// Shared Material 3 menu panel for [DropdownMenu] across the app.
MenuStyle appDropdownMenuStyle() {
  return MenuStyle(
    backgroundColor: WidgetStateProperty.all(AppTheme.surfaceContainerLowest),
    surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
    elevation: WidgetStateProperty.all(10),
    shadowColor: WidgetStateProperty.all(
      Colors.black.withValues(alpha: 0.08),
    ),
    shape: WidgetStateProperty.all(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: AppTheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
    ),
    padding: WidgetStateProperty.all(
      const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    ),
  );
}

/// Outline “pill” for order line [TextField]s — same fill, radius, and padding
/// as [appDropdownInputDecorationTheme] (without a floating label).
InputDecoration orderTableCellDecoration() {
  return InputDecoration(
    filled: true,
    fillColor: AppTheme.surfaceContainerHighest.withValues(alpha: 0.55),
    isDense: false,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(
        color: AppTheme.outlineVariant.withValues(alpha: 0.22),
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(
        color: AppTheme.outlineVariant.withValues(alpha: 0.22),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AppTheme.secondary, width: 1.8),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}

/// Single style for payments (and similar) filter rows: same fill, border,
/// padding, and radius as pill dropdowns — pairs with fixed-height date buttons.
InputDecorationTheme paymentsFilterInputDecorationTheme() {
  final outline = AppTheme.outlineVariant.withValues(alpha: 0.35);
  return InputDecorationTheme(
    filled: true,
    fillColor: AppTheme.surfaceContainerLowest,
    isDense: false,
    floatingLabelBehavior: FloatingLabelBehavior.auto,
    floatingLabelAlignment: FloatingLabelAlignment.start,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: outline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: outline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AppTheme.secondary, width: 1.6),
    ),
    contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    hintStyle: GoogleFonts.assistant(
      color: AppTheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
      fontSize: 14,
    ),
    labelStyle: GoogleFonts.assistant(
      color: AppTheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      fontSize: 13,
    ),
    floatingLabelStyle: GoogleFonts.assistant(
      color: AppTheme.secondary,
      fontWeight: FontWeight.w700,
      fontSize: 12,
    ),
  );
}

/// Default pill height for date / tonal filter chips next to [paymentsFilterInputDecorationTheme] fields.
double get paymentsFilterControlHeight => 62;

/// Shared [InputDecorationTheme] for anchored [DropdownMenu] fields.
InputDecorationTheme appDropdownInputDecorationTheme() {
  return InputDecorationTheme(
    filled: true,
    fillColor: AppTheme.surfaceContainerHighest.withValues(alpha: 0.55),
    floatingLabelBehavior: FloatingLabelBehavior.auto,
    floatingLabelAlignment: FloatingLabelAlignment.start,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(
        color: AppTheme.outlineVariant.withValues(alpha: 0.22),
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(
        color: AppTheme.outlineVariant.withValues(alpha: 0.22),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AppTheme.secondary, width: 1.8),
    ),
    contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    labelStyle: GoogleFonts.assistant(
      color: AppTheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      fontSize: 13,
    ),
    floatingLabelStyle: GoogleFonts.assistant(
      color: AppTheme.secondary,
      fontWeight: FontWeight.w700,
      fontSize: 13,
    ),
  );
}
