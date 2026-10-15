import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/app_config.dart';
import 'package:fleetpilot/ecosystem/ecosystem_access.dart';

void main() {
  const user = '00000000-0000-4000-8000-000000000001';
  const workspace = '00000000-0000-4000-8000-000000000002';
  Map<String, Object> garage(String role) => {'user_id': user,
    'workspace_id': workspace, 'role': role,
    'garage_workspaces': {'name': 'Workshop QA'}};
  EcosystemAccessRepository repository({Object? fleet = const [],
      Object? workshops = const []}) => EcosystemAccessRepository(
    currentUserId: () => user,
    fleetRows: (_) async => fleet, garageRows: (_) async => workshops);

  test('QA opt-in cannot target production or similar-looking URLs', () {
    expect(AppConfig.isEcosystemQaBackend('https://fyestmquqvkdebxxbcky.supabase.co'), isTrue);
    for (final url in ['https://wqhymmtiawfwjikdaujo.supabase.co',
      'http://fyestmquqvkdebxxbcky.supabase.co',
      'https://fyestmquqvkdebxxbcky.supabase.co.evil.test']) {
      expect(AppConfig.isEcosystemQaBackend(url), isFalse);
    }
  });
  test('private customer has no fleet or staff membership', () async {
    final access = await repository().load();
    expect(access.hasFleet, isFalse); expect(access.garages, isEmpty);
  });
  test('all Fleet roles route to existing Fleet, including driver', () async {
    for (final role in ['owner','admin','manager','viewer','driver']) {
      final access = await repository(fleet: [{'user_id': user,
        'company_id': workspace,'role': role}]).load();
      expect(access.hasFleet, isTrue);
    }
  });
  test('mechanic and adviser cannot obtain owner configuration', () async {
    for (final role in ['owner','service_adviser','mechanic']) {
      final access = await repository(workshops: [garage(role)]).load();
      expect(access.garages.single.module, role == 'mechanic'
        ? EcosystemModule.mechanic : EcosystemModule.workshop);
      expect(access.garages.single.canConfigure, role == 'owner');
    }
  });
  test('rejects foreign users, invalid roles, scopes and duplicate memberships', () async {
    for (final rows in [
      [garage('owner')..['user_id']='other'],
      [garage('administrator')],
      [garage('owner')..['workspace_id']='invalid'],
      [garage('owner')..remove('garage_workspaces')],
      [garage('owner'),garage('owner')],
    ]) {
      await expectLater(repository(workshops: rows).load(), throwsFormatException);
    }
  });
  test('failed role lookup never falls back to customer or previous roles', () async {
    final repo = EcosystemAccessRepository(currentUserId: () => user,
      fleetRows: (_) async => [],
      garageRows: (_) async => throw StateError('permission denied'));
    await expectLater(repo.load(), throwsStateError);
  });
  test('account change discards an old in-flight membership result', () async {
    String? current = user;
    final pending = Completer<Object?>();
    final repo = EcosystemAccessRepository(currentUserId: () => current,
      fleetRows: (_) => pending.future, garageRows: (_) async => [garage('owner')]);
    final result = repo.load(); current = 'different-account';
    final expectation = expectLater(result, throwsStateError);
    pending.complete([]); await expectation;
  });
  test('signed-out discovery never issues database queries', () async {
    var calls=0;
    final repo = EcosystemAccessRepository(currentUserId: () => null,
      fleetRows: (_) async { calls++;return []; },
      garageRows: (_) async { calls++;return []; });
    await expectLater(repo.load(), throwsStateError);expect(calls,0);
  });
}
