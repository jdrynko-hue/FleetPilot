import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fleetpilot/data/fleet_repository.dart';
import 'package:fleetpilot/core/app_config.dart';
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
  test('signup and recovery pass the environment callback to Auth transport', () async {
    final requests = <http.Request>[];
    final transport = MockClient((request) async {
      requests.add(request);
      return http.Response(request.url.path.endsWith('/signup') ? jsonEncode({
        'id': '00000000-0000-4000-8000-000000000001', 'aud': 'authenticated',
        'email': 'callback@example.test', 'created_at': '2026-10-16T00:00:00Z',
        'app_metadata': <String, Object>{}, 'user_metadata': <String, Object>{},
      }) : '{}', 200, headers: {'content-type': 'application/json'});
    });
    final client = SupabaseClient('https://callback-test.invalid', 'test-anon',
      httpClient: transport, authOptions: const AuthClientOptions(autoRefreshToken: false));
    addTearDown(() async { await client.dispose(); transport.close(); });
    final repository = FleetRepository(client);
    await repository.signUp(email: 'callback@example.test', password: 'fixture-only-password', portal: 'garage');
    await repository.sendPasswordReset('callback@example.test');
    expect(requests.length, 2);
    final qaBuild = AppConfig.isEcosystemQaBackend(AppConfig.supabaseUrl);
    expect(requests[0].url.queryParameters['redirect_to'], qaBuild ? '$preview?portal=garage' : 'https://flotaryx.com/app/');
    expect(requests[1].url.queryParameters['redirect_to'], qaBuild ? preview : 'https://flotaryx.com/app/');
  });

}
