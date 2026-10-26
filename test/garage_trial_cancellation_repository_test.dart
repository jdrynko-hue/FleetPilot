import 'dart:async';
import 'package:fleetpilot/garage/trial_cancellation_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const qa = 'https://fyestmquqvkdebxxbcky.supabase.co';
  const actor = '00000000-0000-4000-8000-000000000001';
  const workspace = '00000000-0000-4000-8000-000000000002';
  const response = {'status':'canceled', 'canceled_at':'2026-10-26T21:00:00Z'};
  GarageTrialCancellationRepository repo({bool enabled = true, String url = qa,
    String? Function()? user, String? Function()? session,
    required Future<Object?> Function(Map<String, Object>) invoke}) =>
      GarageTrialCancellationRepository(enabled: enabled, supabaseUrl: url,
        currentUserId: user ?? () => actor,
        currentSessionKey: session ?? () => 'synthetic-session', invoke: invoke);

  test('only workspace is sent once, double click cannot repeat cancellation', () async {
    var calls = 0;
    final pending = Completer<Object?>();
    final r = repo(invoke: (body) { calls++; expect(body, {'workspace_id':workspace});
      return pending.future; });
    final first = r.cancel(workspace);
    expect(await r.cancel(workspace), GarageTrialCancellationState.uncertain);
    pending.complete(response);
    expect(await first, GarageTrialCancellationState.canceled);
    expect(calls, 1);
  });
  test('disabled, production, malformed scopes and missing sessions send nothing', () async {
    var calls = 0;
    Future<Object?> invoke(Map<String, Object> _) async { calls++; return response; }
    for (final r in [repo(enabled:false, invoke:invoke),
      repo(url:'https://wqhymmtiawfwjikdaujo.supabase.co', invoke:invoke),
      repo(user:() => null, invoke:invoke), repo(session:() => '', invoke:invoke)]) {
      expect(await r.cancel(workspace), isNot(GarageTrialCancellationState.canceled));
    }
    expect(await repo(invoke:invoke).cancel('forged'), GarageTrialCancellationState.unavailable);
    expect(calls, 0);
  });
  test('same user with replaced session cannot accept old response', () async {
    var session = 'first'; final pending = Completer<Object?>();
    final r = repo(session:() => session, invoke:(_) => pending.future);
    final result = r.cancel(workspace); session = 'replacement'; pending.complete(response);
    expect(await result, GarageTrialCancellationState.uncertain);
  });
  for (final raw in [null, {'status':'active', 'canceled_at':'2026-10-26'},
    {'status':'canceled', 'canceled_at':'invalid'},
    {...response, 'subscription_id':'sub_unexpected'}]) {
    test('malformed result is uncertain: $raw', () async {
      expect(await repo(invoke:(_) async => raw).cancel(workspace),
        GarageTrialCancellationState.uncertain);
    });
  }
  test('transport failure cannot be retried automatically', () async {
    var calls = 0;
    final r = repo(invoke:(_) async { calls++; throw Exception('private'); });
    expect(await r.cancel(workspace), GarageTrialCancellationState.uncertain);
    expect(await r.cancel(workspace), GarageTrialCancellationState.uncertain);
    expect(calls, 1);
  });
}
