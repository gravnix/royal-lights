import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // The Digital Atelier - Light Theme Tokens
  static const Color primary = Color(0xFF000000);
  static const Color onPrimary = Color(0xFFFFFFFF);
  
  static const Color secondary = Color(0xFF735C00); // Amber Radiance (Gold)
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFFED65B);
  static const Color onSecondaryContainer = Color(0xFF745C00);
  
  // Surface Hierarchy
  static const Color surface = Color(0xFFF9F9F9); // Base Layer
  static const Color onSurface = Color(0xFF1A1C1C);
  static const Color onSurfaceVariant = Color(0xFF444748);
  static const Color surfaceContainerLow = Color(0xFFF3F3F3);
  static const Color surfaceContainer = Color(0xFFEEEEEE); // Section Layer
  static const Color surfaceContainerHighest = Color(0xFFE2E2E2); // Default inputs
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF); // Elevated Content Cards
  
  static const Color outline = Color(0xFF747878);
  static const Color outlineVariant = Color(0xFFC4C7C7); // Ghost border
  static const Color error = Color(0xFFBA1A1A);
  static const Color onError = Color(0xFFFFFFFF);
  
  // Custom business colors mapped to semantics
  static const Color primaryGold = secondary;
  static const Color primaryBlue = primary; // re-mapped
  static const Color accentBlue = secondaryContainer; // Fallback to avoid breaking
  static const Color textPrimary = onSurface;
  static const Color textSecondary = onSurfaceVariant;
  static const Color surfaceDark = surface; // Map dark usage to light temporarily
  static const Color surfaceCard = surfaceContainerLowest;
  static const Color surfaceLight = surfaceContainer;
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color paid = Color(0xFF4CAF50);
  static const Color partial = Color(0xFFFF9800);
  static const Color unpaid = Color(0xFFBA1A1A);

  static TextTheme _buildTextTheme() {
    return TextTheme(
      displayLarge: GoogleFonts.assistant(
        fontSize: 56,
        fontWeight: FontWeight.bold,
        letterSpacing: -1.12,
        color: onSurface,
      ),
      headlineMedium: GoogleFonts.assistant(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      titleMedium: GoogleFonts.assistant(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: onSurface,
      ),
      bodyMedium: GoogleFonts.assistant(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: onSurface,
        height: 1.5,
      ),
      labelSmall: GoogleFonts.assistant(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
        color: onSurfaceVariant,
      ),
    );
  }

  // We are replacing darkTheme with the new light theme from the design system,
  // keeping the 'darkTheme' property name for now if it's hardcoded elsewhere,
  // or providing a 'lightTheme' that should be used as the default. Keep darkTheme overriding to Light.
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light, // <--- Crucial change based on DS
      colorScheme: const ColorScheme.light(
        primary: primary,
        onPrimary: onPrimary,
        secondary: secondary,
        onSecondary: onSecondary,
        secondaryContainer: secondaryContainer,
        onSecondaryContainer: onSecondaryContainer,
        surface: surface,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        error: error,
        onError: onError,
        outline: outline,
        outlineVariant: outlineVariant,
        surfaceContainerHighest: surfaceContainerHighest,
      ),
      scaffoldBackgroundColor: surface,
      textTheme: _buildTextTheme(),
      appBarTheme: _buildAppBarTheme(),
      cardTheme: _buildCardTheme(),
      elevatedButtonTheme: _buildElevatedButtonTheme(),
      outlinedButtonTheme: _buildOutlinedButtonTheme(),
      inputDecorationTheme: _buildInputDecorationTheme(),
      dataTableTheme: _buildDataTableTheme(),
      floatingActionButtonTheme: _buildFABTheme(),
      navigationRailTheme: _buildNavigationRailTheme(),
      dialogTheme: _buildDialogTheme(),
      snackBarTheme: _buildSnackBarTheme(),
      dividerTheme: const DividerThemeData(color: outlineVariant, thickness: 1),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _SmoothPageTransitionsBuilder(),
          TargetPlatform.iOS: _SmoothPageTransitionsBuilder(),
          TargetPlatform.macOS: _SmoothPageTransitionsBuilder(),
          TargetPlatform.windows: _SmoothPageTransitionsBuilder(),
        },
      ),
      menuTheme: _buildMenuTheme(),
      menuButtonTheme: _buildMenuButtonTheme(),
      popupMenuTheme: _buildPopupMenuTheme(),
    );
  }

  static AppBarTheme _buildAppBarTheme() {
    return AppBarTheme(
      backgroundColor: surface,
      foregroundColor: onSurface,
      elevation: 0,
      centerTitle: false,
      toolbarHeight: 64,
      titleTextStyle: GoogleFonts.assistant(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
    );
  }

  static CardThemeData _buildCardTheme() {
    return CardThemeData(
      color: surfaceContainerLowest,
      elevation: 0, // No shadow in standard usage, use explicit ambient shadows where needed
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: outlineVariant, width: 0.5),
      ),
      margin: const EdgeInsets.all(8),
    );
  }

  static ElevatedButtonThemeData _buildElevatedButtonTheme() {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        minimumSize: const Size(56, 56),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: GoogleFonts.assistant(fontSize: 18, fontWeight: FontWeight.bold),
        elevation: 4,
        shadowColor: Colors.black26,
      ),
    );
  }

  static OutlinedButtonThemeData _buildOutlinedButtonTheme() {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        minimumSize: const Size(56, 56),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        side: const BorderSide(color: outlineVariant, width: 1.5),
      ),
    );
  }

  static InputDecorationTheme _buildInputDecorationTheme() {
    return InputDecorationTheme(
      filled: true,
      fillColor: surfaceContainerHighest, // default state for inputs
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      floatingLabelAlignment: FloatingLabelAlignment.start,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: outlineVariant, width: 1), // Ghost Border
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: outlineVariant, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: secondary, width: 2), // Beam of light
      ),
      labelStyle: GoogleFonts.assistant(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.0,
        color: onSurfaceVariant,
      ),
      floatingLabelStyle: GoogleFonts.assistant(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: secondary,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    );
  }

  static DataTableThemeData _buildDataTableTheme() {
    return DataTableThemeData(
      headingRowColor: WidgetStateProperty.all(surfaceContainer),
      dataRowColor: WidgetStateProperty.all(surfaceContainerLowest),
      headingTextStyle: GoogleFonts.assistant(
        fontWeight: FontWeight.w700,
        color: onSurface,
        fontSize: 14,
      ),
      dataTextStyle: GoogleFonts.assistant(color: onSurface, fontSize: 13),
      dividerThickness: 0.5,
    );
  }

  static FloatingActionButtonThemeData _buildFABTheme() {
    return const FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: onPrimary,
      elevation: 6,
      shape: CircleBorder(),
    );
  }

  static NavigationRailThemeData _buildNavigationRailTheme() {
    return NavigationRailThemeData(
      backgroundColor: surfaceContainerLowest,
      selectedIconTheme: const IconThemeData(color: primary, size: 28),
      unselectedIconTheme: const IconThemeData(color: onSurfaceVariant, size: 24),
      selectedLabelTextStyle: GoogleFonts.assistant(
        color: primary,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      unselectedLabelTextStyle: GoogleFonts.assistant(
        color: onSurfaceVariant,
        fontSize: 12,
      ),
    );
  }

  static DialogThemeData _buildDialogTheme() {
    return DialogThemeData(
      backgroundColor: surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: GoogleFonts.assistant(
        color: onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  static SnackBarThemeData _buildSnackBarTheme() {
    return SnackBarThemeData(
      backgroundColor: primary,
      contentTextStyle: GoogleFonts.assistant(color: onPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    );
  }

  /// Matches [appDropdownMenuStyle] so MenuAnchor / DropdownMenu defaults stay rounded.
  static MenuThemeData _buildMenuTheme() {
    return MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(surfaceContainerLowest),
        surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
        elevation: WidgetStateProperty.all(10),
        shadowColor: WidgetStateProperty.all(
          Colors.black.withValues(alpha: 0.08),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(
              color: outlineVariant.withValues(alpha: 0.2),
            ),
          ),
        ),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        ),
      ),
    );
  }

  /// Rounds [MenuItemButton] highlights inside dropdown lists (M3 defaults are square).
  static MenuButtonThemeData _buildMenuButtonTheme() {
    return MenuButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  static PopupMenuThemeData _buildPopupMenuTheme() {
    return PopupMenuThemeData(
      color: surfaceContainerLowest,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: outlineVariant.withValues(alpha: 0.2)),
      ),
    );
  }
}

/// Heavier fade + slide for route transitions.
class _SmoothPageTransitionsBuilder extends PageTransitionsBuilder {
  const _SmoothPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const curve = Curves.easeOutQuart;
    final curved = CurvedAnimation(
      parent: animation,
      curve: curve,
      reverseCurve: curve.flipped,
    );
    final opacity = Tween<double>(begin: 0, end: 1).animate(curved);
    final offset = Tween<Offset>(
      begin: const Offset(0.04, 0),
      end: Offset.zero,
    ).animate(curved);
    final scale = Tween<double>(begin: 0.98, end: 1.0).animate(curved);
    return FadeTransition(
      opacity: opacity,
      child: SlideTransition(
        position: offset,
        child: ScaleTransition(
          scale: scale,
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

