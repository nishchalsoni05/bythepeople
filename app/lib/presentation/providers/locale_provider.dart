import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:by_the_people/core/i18n/strings.dart';

const _localeKey = 'app_locale';

/// Current language code: 'en' or 'hi'. Persisted; storage failures never block the app.
final localeProvider = NotifierProvider<LocaleNotifier, String>(LocaleNotifier.new);

class LocaleNotifier extends Notifier<String> {
  @override
  String build() {
    _restore();
    return 'en';
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_localeKey);
      if (!ref.mounted) return;
      if (saved != null && Strings.isSupported(saved)) state = saved;
    } catch (_) {
      // Storage unavailable: keep the default language.
    }
  }

  Future<void> setLocale(String lang) async {
    if (!Strings.isSupported(lang) || lang == state) return;
    state = lang;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_localeKey, lang);
    } catch (_) {
      // Not saved; the choice still applies for this session.
    }
  }
}

/// Translated copy for [key]. Use inside build(): it watches the locale so the widget rebuilds on change.
String tr(WidgetRef ref, String key) => Strings.instance.get(key, ref.watch(localeProvider));

/// Translated copy for [key] without subscribing. Use in callbacks, after awaits, and in toasts.
String trNow(WidgetRef ref, String key) => Strings.instance.get(key, ref.read(localeProvider));
