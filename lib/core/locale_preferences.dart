import 'localization.dart';
import 'locale_storage_stub.dart'
    if (dart.library.js_interop) 'locale_storage_web.dart' as storage;

String? canonicalLanguage(String? value) {
  final code = value?.trim().toLowerCase().split(RegExp('[-_]')).first;
  return supportedLanguages.contains(code) ? code : null;
}

String resolveLanguage({required Uri uri, String? stored, String? device}) =>
    canonicalLanguage(uri.queryParameters['lang']) ??
    canonicalLanguage(stored) ?? canonicalLanguage(device) ?? 'en';

bool _listening = false;
bool _explicitLanguage = false;

void selectAppLanguage(String value) {
  final language = canonicalLanguage(value);
  if (language == null) return;
  _explicitLanguage = true;
  AppLocale.language.value = language;
  storage.writeLanguage(language);
  storage.replaceLanguageInUri(language);
}

void applyProfileLanguage(String language) {
  if (!_explicitLanguage && supportedLanguages.contains(language)) {
    AppLocale.language.value = language;
  }
}

void initializeAppLanguage({required Uri uri, String? device}) {
  final stored = storage.readLanguage();
  _explicitLanguage = canonicalLanguage(uri.queryParameters['lang']) != null ||
      canonicalLanguage(stored) != null;
  AppLocale.language.value = resolveLanguage(
    uri: uri, stored: stored, device: device);
  storage.writeLanguage(AppLocale.language.value);
  if (!_listening) {
    _listening = true;
    AppLocale.language.addListener(() {
      final language = canonicalLanguage(AppLocale.language.value);
      if (language != null) storage.writeLanguage(language);
    });
  }
}
