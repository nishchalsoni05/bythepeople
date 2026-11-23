import 'package:flutter_test/flutter_test.dart';

import 'package:by_the_people/core/i18n/strings.dart';

void main() {
  group('Strings lookup', () {
    test('missing Hindi key falls back to English', () {
      final s = Strings(english: {'only_english': 'Only in English'}, hindi: {'other': 'कुछ'});
      expect(s.get('only_english', 'hi'), 'Only in English');
    });

    test('present Hindi key returns Hindi copy', () {
      final s = Strings(english: {'k': 'Hello'}, hindi: {'k': 'नमस्ते'});
      expect(s.get('k', 'hi'), 'नमस्ते');
      expect(s.get('k', 'en'), 'Hello');
    });

    test('unknown key returns the key itself', () {
      final s = Strings(english: {'k': 'Hello'});
      expect(s.get('missing_key', 'en'), 'missing_key');
      expect(s.get('missing_key', 'hi'), 'missing_key');
    });

    test('unsupported language code uses English', () {
      final s = Strings(english: {'k': 'Hello'}, hindi: {'k': 'नमस्ते'});
      expect(s.get('k', 'fr'), 'Hello');
    });

    test('app table has Hindi copy for every English key', () {
      final table = Strings.instance;
      final missing = [for (final k in table.keys) if (!table.hasHindi(k)) k];
      expect(missing, isEmpty);
    });

    test('app table returns Hindi for the core navigation keys', () {
      expect(Strings.instance.get('nav_home', 'hi'), 'होम');
      expect(Strings.instance.get('nav_calendar', 'hi'), 'कैलेंडर');
      expect(Strings.instance.get('nav_give', 'hi'), 'सेवा');
      expect(Strings.instance.get('nav_profile', 'hi'), 'प्रोफ़ाइल');
    });
  });

  test('isSupported accepts only en and hi', () {
    expect(Strings.isSupported('en'), isTrue);
    expect(Strings.isSupported('hi'), isTrue);
    expect(Strings.isSupported('fr'), isFalse);
  });
}
