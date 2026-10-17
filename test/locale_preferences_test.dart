import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/locale_preferences.dart';
import 'package:fleetpilot/core/locale_uri.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/auth/auth_ui_text.dart';

void main() {
  tearDown(() => initializeAppLanguage(uri: Uri.parse('https://example.test/app/'), device: 'en'));
  for (final language in supportedLanguages) {
    test('explicit $language survives a different saved/device language', () {
      expect(resolveLanguage(uri: Uri.parse('https://example.test/app/?portal=garage&lang=$language'),
        stored: language == 'en' ? 'pl' : 'en', device: 'en-GB'), language);
    });
  }
  test('saved site preference and regional device fallback are supported', () {
    final uri = Uri.parse('https://example.test/app/?lang=unknown');
    expect(resolveLanguage(uri: uri, stored: 'PL_pl', device: 'en'), 'pl');
    expect(resolveLanguage(uri: uri, stored: 'unknown', device: 'de-DE'), 'de');
    expect(resolveLanguage(uri: uri, device: 'zz'), 'en');
  });
  test('selected language is not overwritten by an older account profile', () {
    initializeAppLanguage(uri: Uri.parse('https://example.test/app/?lang=pl'), device: 'en');
    applyProfileLanguage('en');
    expect(AppLocale.language.value, 'pl');
    selectAppLanguage('de');
    applyProfileLanguage('pl');
    expect(AppLocale.language.value, 'de');
    selectAppLanguage('invalid');
    expect(AppLocale.language.value, 'de');
  });
  test('profile fallback works when the user has not chosen a language', () {
    initializeAppLanguage(uri: Uri.parse('https://example.test/app/'), device: 'en');
    applyProfileLanguage('pl');
    expect(AppLocale.language.value, 'pl');
  });
  test('language URL update preserves portal, repeated parameters and auth fragment', () {
    final uri = Uri.parse('https://example.test/app/?portal=garage&invite=a&invite=b&lang=en#type=recovery&access_token=synthetic');
    final updated = withLanguageQuery(uri, 'pl');
    expect(updated.queryParameters['portal'], 'garage');
    expect(updated.queryParametersAll['invite'], ['a', 'b']);
    expect(updated.queryParametersAll['lang'], ['pl']);
    expect(updated.fragment, uri.fragment);
    expect(updated.origin, uri.origin);
    expect(updated.path, '/app/');
  });
  test('all additional auth messages have complete non-English translations', () {
    expect(authMessageKeys.toSet().length, authMessageKeys.length);
    expect(authMessageTranslations.keys.toSet(), supportedLanguages.where((l) => l != 'pl' && l != 'en').toSet());
    for (final entry in authMessageTranslations.entries) {
      expect(entry.value.length, authMessageKeys.length, reason: entry.key);
      for (var i = 0; i < authMessageKeys.length; i++) {
        expect(authText(authMessageKeys[i], 'polski', language: entry.key), isNot(authMessageKeys[i]),
          reason: '${entry.key}: ${authMessageKeys[i]}');
      }
      expect(authText('We sent a confirmation link to {email}. Check your spam folder too.',
        'polski', language: entry.key), contains('{email}'));
    }
  });
}
