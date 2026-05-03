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

  /// Full-screen flows (QR invite) — dark keeps cinematic gradient; light matches home.
  static List<Color> fullScreenGradient(BuildContext context) {
    if (isDark(context)) {
      return const [
        Color(0xFF8B1A2C),
        Color(0xFF3D0C0C),
        Color(0xFF1A0A0A),
        Color(0xFF0D0D0D),
      ];
    }
    return screenGradient(context);
  }

  static Color dialogBackground(BuildContext context) =>
      isDark(context) ? const Color(0xFF1A0A0A) : const Color(0xFFF2ECEC);

  static Color cardBackground(BuildContext context) =>
      isDark(context) ? const Color(0xFF2A1111) : Colors.white;

  static Color textPrimary(BuildContext context) =>
      isDark(context) ? Colors.white : const Color(0xFF1A1A1A);

  static Color textSecondary(BuildContext context) =>
      isDark(context) ? Colors.white70 : Colors.black54;

  /// Replaces white54 / white60 on mixed backgrounds.
  static Color textMuted(BuildContext context) =>
      isDark(context) ? Colors.white70 : const Color(0xFF5C5C5C);

  /// Replaces white38 / white30.
  static Color textDisabled(BuildContext context) =>
      isDark(context) ? Colors.white38 : const Color(0xFF757575);

  /// List row on gradient (1A0A0A @ ~80% in dark).
  static Color listCardBackground(BuildContext context) =>
      isDark(context)
          ? const Color(0xFF1A0A0A).withAlpha(204)
          : Colors.white;

  static Color listCardBackgroundStrong(BuildContext context) =>
      isDark(context)
          ? const Color(0xFF1A0A0A).withAlpha(210)
          : Colors.white;

  static Color listCardBorder(BuildContext context) =>
      isDark(context)
          ? Colors.white.withAlpha(16)
          : const Color(0xFF000000).withAlpha(14);

  static Color listCardBorderMedium(BuildContext context) =>
      isDark(context)
          ? Colors.white.withAlpha(20)
          : const Color(0xFF000000).withAlpha(12);

  static Color bottomSheetBackground(BuildContext context) =>
      isDark(context) ? const Color(0xFF1A0A0A) : const Color(0xFFF2ECEC);

  static Color columnHeaderBackground(BuildContext context) =>
      isDark(context) ? const Color(0xFF2D1515) : const Color(0xFFECE4E4);

  static Color columnHeaderBorder(BuildContext context) =>
      isDark(context)
          ? Colors.white.withAlpha(13)
          : const Color(0xFF000000).withAlpha(10);

  static Color taskColumnBorder(BuildContext context, {required bool activeDrop}) {
    if (activeDrop) {
      return const Color(0xFFE57373).withAlpha(120);
    }
    return isDark(context)
        ? Colors.white.withAlpha(13)
        : const Color(0xFF000000).withAlpha(12);
  }

  static Color surfaceSecondary(BuildContext context) =>
      isDark(context) ? const Color(0xFF2A1111) : const Color(0xFFF0EBEB);

  static Color surfaceSecondaryBorder(BuildContext context) =>
      isDark(context)
          ? Colors.white.withAlpha(38)
          : const Color(0xFF000000).withAlpha(18);

  static Color groupActionSecondary(BuildContext context) =>
      isDark(context) ? const Color(0xFF2A1111) : const Color(0xFFE8E0E0);

  static Color fabMenuPanel(BuildContext context) =>
      isDark(context)
          ? const Color(0xFF1A0A0A).withAlpha(210)
          : Colors.white;

  static Color navBarBackground(BuildContext context) =>
      isDark(context) ? const Color(0xFF0D0D0D) : const Color(0xFFF2ECEC);

  static Color navBarTopBorder(BuildContext context) =>
      isDark(context)
          ? Colors.white.withAlpha(26)
          : const Color(0xFF000000).withAlpha(10);

  static Color navIconInactive(BuildContext context) =>
      isDark(context) ? Colors.white54 : const Color(0xFF6E6E6E);

  static const Color navIconActive = Color(0xFFE57373);

  static Color circularProgressOnBackground(BuildContext context) =>
      isDark(context) ? Colors.white : const Color(0xFF8B1A2C);

  static Color linearTrackBackground(BuildContext context) =>
      isDark(context) ? Colors.white24 : const Color(0xFF000000).withAlpha(18);

  static Color outlineMuted(BuildContext context) =>
      isDark(context)
          ? Colors.white.withAlpha(51)
          : const Color(0xFF000000).withAlpha(22);

  static Color outlineStrong(BuildContext context) =>
      isDark(context)
          ? Colors.white.withAlpha(70)
          : const Color(0xFF000000).withAlpha(35);

  static Color bubbleOutline(BuildContext context) =>
      isDark(context)
          ? Colors.white.withAlpha(18)
          : const Color(0xFF000000).withAlpha(10);

  static Color bubbleFileChipBackground(BuildContext context) =>
      isDark(context)
          ? Colors.black.withAlpha(28)
          : const Color(0xFFF0F0F0);

  static Color bubbleFileChipBorder(BuildContext context) =>
      isDark(context)
          ? Colors.white.withAlpha(20)
          : const Color(0xFF000000).withAlpha(12);

  static Color bubbleFileChipForeground(BuildContext context) =>
      isDark(context) ? Colors.white70 : const Color(0xFF424242);

  static Color composerBarBackground(BuildContext context) =>
      isDark(context)
          ? Colors.black.withAlpha(18)
          : const Color(0xFFEAE4E4);

  static Color replyPreviewBackground(BuildContext context) =>
      isDark(context) ? const Color(0xFF2A1111) : const Color(0xFFE8E0E0);

  static Color avatarPlaceholderBackground(BuildContext context) =>
      isDark(context) ? const Color(0xFF2D1515) : const Color(0xFFE8DFDF);

  static Color avatarPlaceholderLetter(BuildContext context) =>
      isDark(context) ? Colors.white : const Color(0xFF5C1A22);

  static Color dragHandle(BuildContext context) =>
      isDark(context) ? Colors.white24 : Colors.black26;

  static Color imagePreviewErrorBackground(BuildContext context) =>
      isDark(context) ? const Color(0xFF1A0A0A) : const Color(0xFFF5F5F5);

  static Color calendarWeekNavBackground(BuildContext context) =>
      isDark(context)
          ? const Color(0xFF1A0A0A).withAlpha(128)
          : Colors.white.withAlpha(200);

  static Color calendarWeekNavBorder(BuildContext context) =>
      isDark(context)
          ? Colors.white.withAlpha(13)
          : const Color(0xFF000000).withAlpha(12);

  static Color calendarDayBadgeNonToday(BuildContext context) =>
      isDark(context) ? const Color(0xFF2D1515) : const Color(0xFFE8E0E0);

  static Color calendarDayBadgeNonTodayBorder(BuildContext context) =>
      isDark(context)
          ? Colors.white.withAlpha(26)
          : const Color(0xFF000000).withAlpha(14);

  static Color calendarNavIcon(BuildContext context) =>
      isDark(context) ? Colors.white70 : const Color(0xFF4A4A4A);

  static Color calendarFabBorder(BuildContext context) =>
      isDark(context)
          ? Colors.white.withAlpha(77)
          : const Color(0xFF000000).withAlpha(18);

  static Color panelTranslucent(BuildContext context) =>
      isDark(context)
          ? const Color(0xFF1A0A0A).withAlpha(90)
          : Colors.white.withAlpha(230);

  static Color panelTranslucentStrong(BuildContext context) =>
      isDark(context)
          ? const Color(0xFF1A0A0A).withAlpha(120)
          : Colors.white.withAlpha(242);
}
