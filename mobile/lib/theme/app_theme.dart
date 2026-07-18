import 'package:flutter/material.dart';

/// Brand colors shared by FlowChat screens and reusable widgets.
abstract final class FlowChatColors {
  static const primary = Color(0xFF7B19D8);
  static const primaryDark = Color(0xFFB866FF);
  static const pink = Color(0xFFFF66CC);
  static const cyan = Color(0xFF66E5E5);

  static const lightBackground = Color(0xFFFCFAFF);
  static const lightSurface = Color(0xFFFFFFFF);
  static const darkBackground = Color(0xFF272735);
  static const darkSurface = Color(0xFF1F1F2B);
  static const darkSurfaceContainer = Color(0xFF303040);

  static const online = Color(0xFF20D873);
  static const offline = Color(0xFF9CA3AF);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, pink],
  );
}

/// Material 3 theme used by the mobile application.
abstract final class AppTheme {
  static final ThemeData lightTheme = _buildTheme(Brightness.light);
  static final ThemeData darkTheme = _buildTheme(Brightness.dark);

  // Short aliases make wiring MaterialApp concise.
  static ThemeData get light => lightTheme;
  static ThemeData get dark => darkTheme;

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final primary = isDark
        ? FlowChatColors.primaryDark
        : FlowChatColors.primary;
    final background = isDark
        ? FlowChatColors.darkBackground
        : FlowChatColors.lightBackground;
    final surface = isDark
        ? FlowChatColors.darkSurface
        : FlowChatColors.lightSurface;

    final seededScheme = ColorScheme.fromSeed(
      seedColor: FlowChatColors.primary,
      brightness: brightness,
    );
    final scheme = seededScheme.copyWith(
      primary: primary,
      onPrimary: isDark ? const Color(0xFF210035) : Colors.white,
      secondary: FlowChatColors.pink,
      onSecondary: isDark ? const Color(0xFF3A0027) : Colors.white,
      tertiary: FlowChatColors.cyan,
      surface: surface,
      onSurface: isDark ? const Color(0xFFE8E7EF) : const Color(0xFF202332),
      outline: isDark ? const Color(0xFF575568) : const Color(0xFFD9D2E2),
      outlineVariant: isDark
          ? const Color(0xFF3D3B4B)
          : const Color(0xFFECE5F2),
      error: isDark ? const Color(0xFFFFB4AB) : const Color(0xFFBA1A1A),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: FlowChatColors.primary.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? FlowChatColors.darkSurfaceContainer
            : const Color(0xFFF8F4FC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.78),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        errorMaxLines: 2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.error, width: 1.8),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          backgroundColor: primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: primary.withValues(alpha: 0.38),
          disabledForegroundColor: scheme.onPrimary.withValues(alpha: 0.78),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: primary,
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFFE8E7EF)
            : const Color(0xFF292532),
        contentTextStyle: TextStyle(
          color: isDark ? const Color(0xFF292532) : Colors.white,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: 0.16),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected)
                ? primary
                : scheme.onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          );
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
    );
  }
}
