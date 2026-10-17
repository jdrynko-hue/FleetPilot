import 'dart:js_interop';
import 'locale_uri.dart';

@JS('localStorage')
external _LocaleStorage get _storage;

@JS('location.href')
external JSString get _href;
@JS('history')
external _LocaleHistory get _history;

extension type _LocaleHistory._(JSObject _) implements JSObject {
  external void replaceState(JSAny? state, JSString title, JSString url);
  external JSAny? get state;
}

extension type _LocaleStorage._(JSObject _) implements JSObject {
  external JSString? getItem(JSString key);
  external void setItem(JSString key, JSString value);
}

String? readLanguage() {
  try { return _storage.getItem('fleetpilot_site_lang'.toJS)?.toDart; }
  catch (_) { return null; }
}

void writeLanguage(String language) {
  try { _storage.setItem('fleetpilot_site_lang'.toJS, language.toJS); }
  catch (_) { /* Private browsing/storage restrictions must not block login. */ }
}

void replaceLanguageInUri(String language) {
  try {
    final uri = Uri.parse(_href.toDart);
    final updated = withLanguageQuery(uri, language);
    _history.replaceState(_history.state, ''.toJS, updated.toString().toJS);
  } catch (_) { /* The in-memory selection still works without History access. */ }
}
