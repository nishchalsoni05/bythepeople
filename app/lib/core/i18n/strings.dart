/// Static UI copy in English and Hindi. A missing Hindi key falls back to English,
/// and an unknown key falls back to the key itself, so a gap never shows a blank label.
class Strings {
  Strings({required Map<String, String> english, Map<String, String> hindi = const {}})
      : _english = Map.unmodifiable(english),
        _hindi = Map.unmodifiable(hindi);

  static const supported = ['en', 'hi'];

  static bool isSupported(String lang) => supported.contains(lang);

  /// The app-wide table.
  static final Strings instance = Strings(english: _englishCopy, hindi: _hindiCopy);

  final Map<String, String> _english;
  final Map<String, String> _hindi;

  Iterable<String> get keys => _english.keys;

  bool hasHindi(String key) => _hindi.containsKey(key);

  String get(String key, String lang) {
    if (lang == 'hi') {
      final hi = _hindi[key];
      if (hi != null) return hi;
    }
    return _english[key] ?? key;
  }
}

const _englishCopy = <String, String>{
  'nav_home': 'Home',
  'nav_calendar': 'Calendar',
  'nav_give': 'Give',
  'nav_profile': 'Profile',
  'home_good_morning': 'Good morning',
  'home_good_afternoon': 'Good afternoon',
  'home_good_evening': 'Good evening',
  'home_open_needs': 'Open needs',
  'home_in_action': 'In action',
  'home_pledged': 'Pledged',
  'home_fulfilled': 'Fulfilled',
  'home_resolved': 'Fulfilled',
  'home_urgent': 'Urgent right now',
  'home_recent_impact': 'Recent impact',
  'home_recent_activity': 'Recent impact',
  'create_post_need': 'Post a need',
  'create_start_event': 'Start an event',
  'create_donate_surplus': 'Donate surplus',
  'cat_food': 'Food',
  'cat_clothes': 'Clothes',
  'cat_money': 'Money',
  'cat_medicine': 'Medicine',
  'cat_stationery': 'Stationery',
  'cat_volunteers': 'Volunteers',
  'cat_other': 'Other',
  'insights_title': 'Insights',
  'events_title': 'Events',
  'surplus_title': 'Surplus',
  'needs_title': 'Needs',
  'reminders_title': 'Reminders',
  'profile_language': 'Language',
  'language_english': 'English',
  'language_hindi': 'Hindi',
  'reminder_set': 'Reminder set',
};

const _hindiCopy = <String, String>{
  'nav_home': 'होम',
  'nav_calendar': 'कैलेंडर',
  'nav_give': 'सेवा',
  'nav_profile': 'प्रोफ़ाइल',
  'home_good_morning': 'सुप्रभात',
  'home_good_afternoon': 'शुभ दोपहर',
  'home_good_evening': 'शुभ संध्या',
  'home_open_needs': 'खुली ज़रूरतें',
  'home_in_action': 'कार्रवाई में',
  'home_pledged': 'वादा किया',
  'home_fulfilled': 'पूरी हुईं',
  'home_resolved': 'पूरी हुईं',
  'home_urgent': 'अभी ज़रूरी',
  'home_recent_impact': 'हाल का असर',
  'home_recent_activity': 'हाल का असर',
  'create_post_need': 'ज़रूरत बताएँ',
  'create_start_event': 'कार्यक्रम शुरू करें',
  'create_donate_surplus': 'अतिरिक्त सामान दें',
  'cat_food': 'भोजन',
  'cat_clothes': 'कपड़े',
  'cat_money': 'धन',
  'cat_medicine': 'दवाइयाँ',
  'cat_stationery': 'स्टेशनरी',
  'cat_volunteers': 'स्वयंसेवक',
  'cat_other': 'अन्य',
  'insights_title': 'जानकारी',
  'events_title': 'कार्यक्रम',
  'surplus_title': 'अतिरिक्त सामान',
  'needs_title': 'ज़रूरतें',
  'reminders_title': 'याद दिलाने वाले',
  'profile_language': 'भाषा',
  'language_english': 'English',
  'language_hindi': 'हिन्दी',
  'reminder_set': 'याद सेट हो गई',
};
