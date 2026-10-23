import 'package:flutter/material.dart';

import 'motion.dart';

/// Token warna dari Design.md bagian 3.
abstract final class AppColors {
  static const background = Color(0xFFFBF6EE);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF1E7DA);
  static const cell = Color(0xFFFBF6EE);
  static const border = Color(0xFFE9DCCB);
  static const inputBorder = Color(0xFFDCCBB6);
  static const primary = Color(0xFF6B3E26);
  static const onPrimary = Color(0xFFFFF8EF);
  static const onPrimaryMuted = Color(0xFFE7D3BC);
  static const primaryContainer = Color(0xFFF1E2CF);
  static const onPrimaryContainer = Color(0xFF5A3420);
  static const text = Color(0xFF2B1D14);
  static const textMuted = Color(0xFF6F5E52);
  static const success = Color(0xFF1F5C38);
  static const successContainer = Color(0xFFDDF1E4);
  static const warning = Color(0xFF7A4A00);
  static const warningContainer = Color(0xFFFFF0D4);
  static const danger = Color(0xFF9C2219);
  static const dangerContainer = Color(0xFFFBE4E2);
  static const dangerStrong = Color(0xFFB3261E);
  static const accentWarm = Color(0xFFB8865B);
  static const barNeutral = Color(0xFFC9A27E);
  static const dashed = Color(0xFFB99572);
}

/// Pasangan warna status (Design.md bagian 8), diambil lewat
/// `Theme.of(context).extension<StatusColors>()!`.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.danger,
    required this.dangerContainer,
  });

  static const light = StatusColors(
    success: AppColors.success,
    successContainer: AppColors.successContainer,
    warning: AppColors.warning,
    warningContainer: AppColors.warningContainer,
    danger: AppColors.danger,
    dangerContainer: AppColors.dangerContainer,
  );

  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;
  final Color danger;
  final Color dangerContainer;

  @override
  StatusColors copyWith({
    Color? success,
    Color? successContainer,
    Color? warning,
    Color? warningContainer,
    Color? danger,
    Color? dangerContainer,
  }) => StatusColors(
    success: success ?? this.success,
    successContainer: successContainer ?? this.successContainer,
    warning: warning ?? this.warning,
    warningContainer: warningContainer ?? this.warningContainer,
    danger: danger ?? this.danger,
    dangerContainer: dangerContainer ?? this.dangerContainer,
  );

  @override
  StatusColors lerp(StatusColors? other, double t) {
    if (other == null) return this;
    return StatusColors(
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
    );
  }
}

const _tabular = [FontFeature.tabularFigures()];

const _bodyFont = 'PlusJakartaSans';
const _titleFont = 'Fraunces';

/// Tema terang (MVP): Plus Jakarta Sans untuk semua teks, Fraunces 600 untuk
/// judul layar. Font dibundel di assets/fonts.
ThemeData buildAppTheme() {
  const scheme = ColorScheme.light(
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primaryContainer,
    onPrimaryContainer: AppColors.onPrimaryContainer,
    secondary: AppColors.primary,
    onSecondary: AppColors.onPrimary,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.textMuted,
    outline: AppColors.inputBorder,
    outlineVariant: AppColors.border,
    error: AppColors.danger,
    onError: AppColors.surface,
    errorContainer: AppColors.dangerContainer,
    onErrorContainer: AppColors.danger,
  );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: _bodyFont,
  );
  final text = base.textTheme.apply(
    bodyColor: AppColors.text,
    displayColor: AppColors.text,
  );
  TextStyle? tabular(TextStyle? style) =>
      style?.copyWith(fontFeatures: _tabular);
  final radius12 = BorderRadius.circular(12);

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    textTheme: text.copyWith(
      displaySmall: tabular(
        text.displaySmall?.copyWith(fontSize: 36, fontWeight: FontWeight.w700),
      ),
      headlineMedium: text.headlineMedium?.copyWith(
        fontFamily: _titleFont,
        fontSize: 28,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: text.headlineSmall?.copyWith(
        fontFamily: _titleFont,
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: tabular(
        text.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      bodyLarge: tabular(text.bodyLarge?.copyWith(fontSize: 15)),
      bodyMedium: tabular(text.bodyMedium?.copyWith(fontSize: 14)),
      bodySmall: tabular(
        text.bodySmall?.copyWith(fontSize: 13, color: AppColors.textMuted),
      ),
      labelSmall: text.labelSmall?.copyWith(fontSize: 12),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: text.headlineSmall?.copyWith(
        fontFamily: _titleFont,
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.surfaceMuted,
      thickness: 1,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.textMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.textMuted,
        ),
      ),
    ),
    // Rel navigasi tablet (FR-21.2), serupa navigasi bawah.
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primaryContainer,
      selectedIconTheme: IconThemeData(color: AppColors.primary),
      unselectedIconTheme: IconThemeData(color: AppColors.textMuted),
      selectedLabelTextStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
      ),
      unselectedLabelTextStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textMuted,
      ),
    ),
    // Lembar bawah tidak melebar penuh di tablet (FR-21.6).
    bottomSheetTheme: const BottomSheetThemeData(
      constraints: BoxConstraints(maxWidth: 640),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // Lebar penuh di bilah bawah diatur pemanggil (SizedBox), agar tombol
        // kecil di AppBar atau Row tidak meminta lebar tak terhingga.
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        shape: RoundedRectangleBorder(borderRadius: radius12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: radius12,
        borderSide: const BorderSide(color: AppColors.inputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius12,
        borderSide: const BorderSide(color: AppColors.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius12,
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    ),
    // Gerak (Design.md bagian Gerak, FR-11.6, FR-11.9).
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: AppPageTransitionsBuilder(),
        TargetPlatform.iOS: AppPageTransitionsBuilder(),
        TargetPlatform.windows: AppPageTransitionsBuilder(),
        TargetPlatform.linux: AppPageTransitionsBuilder(),
        TargetPlatform.macOS: AppPageTransitionsBuilder(),
      },
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.text,
      contentTextStyle: const TextStyle(
        fontFamily: _bodyFont,
        fontSize: 14,
        color: AppColors.onPrimary,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    extensions: const [StatusColors.light],
  );
}
