import 'dart:async';

import 'package:fleetpilot/data/models.dart';
import 'package:fleetpilot/shell/fleet_membership_controller.dart';
import 'package:flutter_test/flutter_test.dart';

CompanyMembership member(String id, [String role = 'owner']) => CompanyMembership(
  companyId: id, companyName: id, role: role, currency: 'GBP');

void main() {
  late String? account;
  late List<Completer<List<CompanyMembership>>> requests;
  late FleetMembershipController controller;
  setUp(() {
    account = 'account-a';
    requests = [];
    controller = FleetMembershipController(
      memberships: [member('a'), member('b')], selectedId: 'b',
      currentAccountId: () => account,
      load: () {
        final response = Completer<List<CompanyMembership>>();
        requests.add(response);
        return response.future;
      });
  });
  tearDown(() => controller.dispose());

  test('refresh retains selection with updated role', () async {
    final pending = controller.refresh();
    expect(controller.loading, isTrue);
    requests.single.complete([member('a'), member('b', 'viewer')]);
    await pending;
    expect(controller.selected!.companyId, 'b');
    expect(controller.selected!.role, 'viewer');
    expect(controller.loading, isFalse);
  });

  test('removed fleet falls back only to an authorized membership', () async {
    final pending = controller.refresh();
    requests.single.complete([member('a')]);
    await pending;
    expect(controller.selected!.companyId, 'a');
    controller.select('b');
    expect(controller.selected!.companyId, 'a');
  });

  test('removing all memberships clears the previous fleet', () async {
    final pending = controller.refresh();
    requests.single.complete([]);
    await pending;
    expect(controller.memberships, isEmpty);
    expect(controller.selected, isNull);
    expect(controller.failed, isFalse);
  });

  test('access failure clears stale controls and retry can recover', () async {
    final pending = controller.refresh();
    requests.single.completeError(StateError('private transport detail'));
    await pending;
    expect(controller.failed, isTrue);
    expect(controller.selected, isNull);
    final retry = controller.refresh();
    requests.last.complete([member('c', 'driver')]);
    await retry;
    expect(controller.failed, isFalse);
    expect(controller.selected!.companyId, 'c');
    expect(controller.selected!.role, 'driver');
  });

  for (final staleFails in [false, true]) {
    test('newest access response wins (stale failure=$staleFails)', () async {
      final old = controller.refresh();
      final latest = controller.refresh();
      requests.last.complete([member('b', 'viewer')]);
      await latest;
      if (staleFails) {
        requests.first.completeError(StateError('old request'));
      } else {
        requests.first.complete([member('b', 'owner')]);
      }
      await old;
      expect(controller.selected!.role, 'viewer');
      expect(controller.loading, isFalse);
      expect(controller.failed, isFalse);
    });
  }

  for (final nextAccount in <String?>['account-b', null]) {
    test('account transition suppresses pending access notification ($nextAccount)', () async {
      var notifications = 0;
      controller.addListener(() => notifications++);
      final pending = controller.refresh();
      expect(notifications, 1);
      account = nextAccount;
      requests.single.complete([member('private-old-account')]);
      await pending;
      expect(notifications, 1);
      expect(controller.selected!.companyId, 'b');
      await controller.refresh();
      expect(requests.length, 1);
      controller.select('a');
      expect(notifications, 1);
    });
  }

  test('disposed controller ignores success and failure completion', () async {
    final pending = controller.refresh();
    final newer = controller.refresh();
    controller.dispose();
    // Use a fresh controller for tearDown; the original is already disposed.
    controller = FleetMembershipController(memberships: [], selectedId: '',
      load: () async => [], currentAccountId: () => account);
    requests.first.complete([member('old')]);
    requests.last.completeError(StateError('old failure'));
    await Future.wait([pending, newer]);
  });

  test('selector accepts authorized fleet and exposes immutable membership list', () {
    controller.select('a');
    expect(controller.selected!.companyId, 'a');
    controller.select('foreign');
    expect(controller.selected!.companyId, 'a');
    expect(() => controller.memberships.clear(), throwsUnsupportedError);
  });
}
