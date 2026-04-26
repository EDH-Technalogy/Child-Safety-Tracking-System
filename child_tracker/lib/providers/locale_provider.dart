import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  static const String _localeKey = 'app_locale';
  static const Set<String> _supportedLocaleCodes = {'en', 'ps', 'fa'};

  Locale _locale = const Locale('en');
  bool _isLoaded = false;

  Locale get locale => _locale;
  bool get isLoaded => _isLoaded;

  bool get isRtl =>
      _locale.languageCode == 'ps' || _locale.languageCode == 'fa';

  LocaleProvider({bool loadSavedLocale = true}) {
    if (loadSavedLocale) {
      restoreSavedLocale();
    }
  }

  static Future<LocaleProvider> load() async {
    final provider = LocaleProvider(loadSavedLocale: false);
    await provider.restoreSavedLocale(notify: false);
    return provider;
  }

  String _normalizeLocaleCode(String? rawCode) {
    var localeCode = rawCode?.trim() ?? '';

    if (localeCode == 'dr' || localeCode == 'prs') {
      return 'fa';
    }

    if (!_supportedLocaleCodes.contains(localeCode)) {
      return 'en';
    }

    return localeCode;
  }

  Future<void> restoreSavedLocale({bool notify = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final storedLocaleCode = prefs.getString(_localeKey);
    final localeCode = _normalizeLocaleCode(storedLocaleCode);

    if (storedLocaleCode != localeCode) {
      await prefs.setString(_localeKey, localeCode);
    }

    _locale = Locale(localeCode);
    _isLoaded = true;

    debugPrint(
      '[LocaleProvider] restored locale=$localeCode stored=$storedLocaleCode notify=$notify',
    );

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> setLocale(Locale locale) async {
    final nextLocale = Locale(_normalizeLocaleCode(locale.languageCode));
    final previousLocale = _locale;

    debugPrint(
      '[LocaleProvider] change requested current=${previousLocale.languageCode} selected=${nextLocale.languageCode}',
    );

    if (_locale == nextLocale) {
      debugPrint(
        '[LocaleProvider] change skipped locale=${nextLocale.languageCode} already active',
      );
      return;
    }

    _locale = nextLocale;
    _isLoaded = true;
    notifyListeners();

    debugPrint(
      '[LocaleProvider] locale applied current=${_locale.languageCode} previous=${previousLocale.languageCode}',
    );

    unawaited(_saveLocale(nextLocale.languageCode));
  }

  Future<void> _saveLocale(String localeCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_localeKey, localeCode);
      debugPrint('[LocaleProvider] locale saved locale=$localeCode');
    } catch (e) {
      debugPrint('[LocaleProvider] failed to save locale=$localeCode: $e');
    }
  }

  void toggleLocale() {
    if (_locale.languageCode == 'en') {
      setLocale(const Locale('ps'));
    } else {
      setLocale(const Locale('en'));
    }
  }
}
