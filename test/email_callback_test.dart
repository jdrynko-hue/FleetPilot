import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/auth/email_callback.dart';

void main() {
  const qa = 'https://fyestmquqvkdebxxbcky.supabase.co';
  const preview = 'https://flotaryx-qa-preview.fairdrake9.chatgpt.site/app/';
  test('production callback is unchanged even with QA configuration', () {
    expect(authEmailCallback(backendUrl: 'https://wqhymmtiawfwjikdaujo.supabase.co',
      configuredQaCallback: preview, portal: 'garage'), 'https://flotaryx.com/app/');
  });
  test('QA preserves only explicit panel intents, without auth query data', () {
    for (final portal in ['fleet', 'garage', 'customer', 'search']) {
      expect(authEmailCallback(backendUrl: qa, configuredQaCallback: preview,
        portal: portal), '$preview?portal=$portal');
    }
    expect(authEmailCallback(backendUrl: qa, configuredQaCallback: preview,
      portal: 'https://evil.example/'), preview);
    expect(authEmailCallback(backendUrl: qa, configuredQaCallback: preview), preview);
  });
  for (final invalid in ['', 'https://flotaryx.com/app/',
    'https://www.flotaryx.com/app/', 'http://qa.example/app/',
    'https://user:secret@qa.example/app/', 'https://qa.example:8443/app/',
    'https://qa.example/', 'https://qa.example/app/?redirect=https://evil.example',
    'https://qa.example/app/#access_token=private']) {
    test('QA rejects unsafe or missing callback: $invalid', () {
      expect(() => authEmailCallback(backendUrl: qa, configuredQaCallback: invalid),
        throwsStateError);
    });
  }
}
