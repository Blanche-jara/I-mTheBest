import 'package:flutter/material.dart';

/// 다크 모던 테마 및 공용 색상 토큰.
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF0E1116);
  static const Color surface = Color(0xFF161B22);
  static const Color surfaceAlt = Color(0xFF1C232D);
  static const Color border = Color(0xFF2A323D);
  static const Color primary = Color(0xFF4F8CFF);
  static const Color accent = Color(0xFF7C5CFF);
  static const Color success = Color(0xFF3FB950);
  static const Color warning = Color(0xFFD29922);
  static const Color danger = Color(0xFFF85149);
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF8B98A5);

  /// 채널별 고정 색상(차트/막대 공유).
  static const Map<String, Color> channel = {
    'frame_entropy': Color(0xFF4F8CFF),
    'motion': Color(0xFF3FB950),
    'spectral': Color(0xFFD29922),
    'cheer': Color(0xFFF778BA),
    'loudness': Color(0xFF56D4DD),
    'fused': Color(0xFFE6EDF3),
  };

  static Color forChannel(String name) => channel[name] ?? textSecondary;
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.primary,
    secondary: AppColors.accent,
    surface: AppColors.surface,
    error: AppColors.danger,
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onSurface: AppColors.textPrimary,
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'Segoe UI',
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      isDense: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: AppColors.surfaceAlt,
      side: BorderSide(color: AppColors.border),
      labelStyle: TextStyle(color: AppColors.textPrimary, fontSize: 12),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.surfaceAlt,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.primary
            : AppColors.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.primary.withValues(alpha: 0.4)
            : AppColors.surfaceAlt,
      ),
    ),
  );
}

/// 한국어 라벨 맵 (config.CHANNEL_LABELS_KO + fused).
const Map<String, String> channelLabelsKo = {
  'frame_entropy': '프레임 엔트로피',
  'motion': '모션 엔트로피',
  'spectral': '스펙트럼 변화',
  'cheer': '환호성',
  'loudness': '음량 변화',
  'fused': '융합 surprise',
};

/// 표준 채널 순서 (config.CHANNELS).
const List<String> kChannels = [
  'frame_entropy',
  'motion',
  'spectral',
  'cheer',
  'loudness',
];

String channelLabel(String name) => channelLabelsKo[name] ?? name;

/// 초 -> mm:ss 포맷.
String formatMmss(num seconds) {
  final total = seconds.isFinite ? seconds.round() : 0;
  final m = (total ~/ 60).toString().padLeft(2, '0');
  final s = (total % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
