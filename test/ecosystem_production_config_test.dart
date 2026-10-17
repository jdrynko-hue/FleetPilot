import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/app_config.dart';

void main() {
  const qa = 'https://fyestmquqvkdebxxbcky.supabase.co';
  const production = 'https://wqhymmtiawfwjikdaujo.supabase.co';
  test('each deployment requires its own explicit opt-in', () {
    expect(AppConfig.ecosystemEnabledFor(qa), isFalse);
    expect(AppConfig.ecosystemEnabledFor(production), isFalse);
    expect(AppConfig.ecosystemEnabledFor(qa, qa: true), isTrue);
    expect(AppConfig.ecosystemEnabledFor(production, production: true), isTrue);
    expect(AppConfig.ecosystemEnabledFor(qa, production: true), isFalse);
    expect(AppConfig.ecosystemEnabledFor(production, qa: true), isFalse);
  });
  test('flags cannot enable untrusted, insecure or lookalike backends', () {
    for (final url in ['http://wqhymmtiawfwjikdaujo.supabase.co',
      '$production.evil.test', '$production/', '$qa.evil.test',
      'https://example.test', '']) {
      expect(AppConfig.ecosystemEnabledFor(url, qa: true, production: true), isFalse);
    }
  });
}
