import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  static const String _localeKey = 'app_locale';

  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  bool get isRtl =>
      _locale.languageCode == 'ps' || _locale.languageCode == 'fa';

  LocaleProvider() {
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    var localeCode = prefs.getString(_localeKey) ?? 'en';

    // Migrate old invalid language codes to valid ones
    if (localeCode == 'dr' || localeCode == 'prs') {
      localeCode = 'fa';
      await prefs.setString(_localeKey, 'fa');
    }

    _locale = Locale(localeCode);
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;

    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, locale.languageCode);
    notifyListeners();
  }

  void toggleLocale() {
    if (_locale.languageCode == 'en') {
      setLocale(const Locale('ps'));
    } else {
      setLocale(const Locale('en'));
    }
  }
}
