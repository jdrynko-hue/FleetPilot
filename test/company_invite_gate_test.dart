import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/auth/company_gate.dart';
import 'package:fleetpilot/auth/create_company_screen.dart';
import 'package:fleetpilot/core/localization.dart';

void main() {
  setUp(() => AppLocale.language.value = 'en');

  testWidgets('failed invite shows an actionable error instead of fleet creation',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
      home: CompanyGate(
        inviteCode: 'invalid-invite',
        acceptInvite: (code) async {
          attempts++;
          throw StateError('PRIVATE DATA');
        },
        loadMemberships: () async => [],
      ),
    ));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(find.byKey(const Key('fleet_invite_error_title')), findsOneWidget);
    expect(find.byType(CreateCompanyScreen), findsNothing);
    expect(find.textContaining('PRIVATE DATA'), findsNothing);
  });

  testWidgets('retry can succeed after a temporary error', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
      home: CompanyGate(
        inviteCode: 'test-invite',
        acceptInvite: (code) async {
          attempts++;
          if (attempts == 1) throw StateError('temporarily unavailable');
        },
        loadMemberships: () async => [],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fleet_invite_error_title')), findsOneWidget);

    await tester.tap(find.byKey(const Key('retry_fleet_invite')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byKey(const Key('fleet_invite_error_title')), findsNothing);
    expect(find.byType(CreateCompanyScreen), findsOneWidget);
  });

  testWidgets('continue without invitation is explicit', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
      home: CompanyGate(
        inviteCode: 'expired-invite',
        acceptInvite: (code) async {
          attempts++;
          throw StateError('expired');
        },
        loadMemberships: () async => [],
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continue_without_fleet_invite')));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(find.byType(CreateCompanyScreen), findsOneWidget);
  });

  testWidgets('Polish invitation error has clear instructions', (tester) async {
    AppLocale.language.value = 'pl';
    addTearDown(() => AppLocale.language.value = 'en');
    await tester.pumpWidget(MaterialApp(
      home: CompanyGate(
        inviteCode: 'mismatched',
        acceptInvite: (code) async => throw StateError('email mismatch'),
        loadMemberships: () async => [],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Nie można przyjąć zaproszenia'), findsOneWidget);
    expect(find.text('Przejdź bez zaproszenia'), findsOneWidget);
  });
}
