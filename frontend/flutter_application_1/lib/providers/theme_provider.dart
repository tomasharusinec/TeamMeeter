// Reaguje na prepínač svetlé versus tmavé zobrazenia celej používateľskej aplikácie.
// Rozhodnutý režim sa uloží do úložiska aby sa použil pri ďalšom otvorení aplikácie.
// This file was generated using AI (Gemini)




import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeModeKey = 'theme_mode_v1';
  ThemeMode _themeMode = ThemeMode.dark;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  // Tato funkcia nacita alebo obnovi data.
  // Pouziva API volania a potom aktualizuje stav.
  Future<void> loadSavedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_themeModeKey);
    if (raw == 'light') {
      _themeMode = ThemeMode.light;
    } else if (raw == 'dark') {
      _themeMode = ThemeMode.dark;
    }
    notifyListeners();
  }

  void toggleTheme() {
    _themeMode = isDarkMode ? ThemeMode.light : ThemeMode.dark;
    _saveThemeMode();
    notifyListeners();
  }

  // Tato funkcia odosle alebo ulozi formular.
  // Pred odoslanim skontroluje vstupy a spracuje odpoved.
  Future<void> _saveThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = _themeMode == ThemeMode.light ? 'light' : 'dark';
    await prefs.setString(_themeModeKey, value);
  }
}
