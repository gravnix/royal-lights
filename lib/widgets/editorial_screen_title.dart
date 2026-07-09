import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_theme.dart';

/// Large page title + gold underline accent (payments / suppliers / assemblies).
class EditorialScreenTitle extends StatelessWidget {
  const EditorialScreenTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.only(left: 32, right: 32, top: 28, bottom: 24),
  });

  final String title;
  final Widget? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.assistant(
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: AppTheme.onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 4,
                  width: 60,
                  decoration: BoxDecoration(
                    color: AppTheme.secondary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 12),
                  subtitle!,
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
