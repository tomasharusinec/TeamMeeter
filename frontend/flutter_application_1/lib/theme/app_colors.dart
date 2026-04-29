import 'package:flutter/material.dart';

class AppColors {
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static List<Color> screenGradient(BuildContext context) {
    if (isDark(context)) {
      return const [
        Color(0xFF8B1A2C),
        Color(0xFF3D0C0C),
        Color(0xFF1A0A0A),
        Color(0xFF0D0D0D),
      ];
    }
    return const [
      Color(0xFF8B1A2C),
      Color(0xFFE8DFDF),
      Color(0xFFE3DDDD),
      Color(0xFFD8D2D2),
    ];
  }

  static Color dialogBackground(BuildContext context) =>
      isDark(context) ? const Color(0xFF1A0A0A) : const Color(0xFFF2ECEC);

  static Color cardBackground(BuildContext context) =>
      isDark(context) ? const Color(0xFF2A1111) : Colors.white;

  static Color textPrimary(BuildContext context) =>
      isDark(context) ? Colors.white : const Color(0xFF1A1A1A);

  static Color textSecondary(BuildContext context) =>
      isDark(context) ? Colors.white70 : Colors.black54;
}
