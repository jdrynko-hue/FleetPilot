import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/app_config.dart';

void main() {
  test('Smart Maintenance remains disabled without explicit opt-in', () {
    expect(AppConfig.smartMaintenanceQaEnabledFor(
      'https://fyestmquqvkdebxxbcky.supabase.co', requested: false), isFalse);
  });

  test('Smart Maintenance QA is restricted to exact isolated backend', () {
    expect(AppConfig.smartMaintenanceQaEnabledFor(
      'https://fyestmquqvkdebxxbcky.supabase.co', requested: true), isTrue);
    expect(AppConfig.smartMaintenanceQaEnabledFor(
      'https://wqhymmtiawfwjikdaujo.supabase.co', requested: true), isFalse);
    expect(AppConfig.smartMaintenanceQaEnabledFor(
      'https://untrusted.example', requested: true), isFalse);
  });
}
