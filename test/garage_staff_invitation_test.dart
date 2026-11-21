import 'dart:async';

import 'package:fleetpilot/ecosystem/ecosystem_access.dart';
import 'package:fleetpilot/ecosystem/ecosystem_gate.dart';
import 'package:fleetpilot/garage/staff_invitation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _code = '0123456789abcdef0123456789abcdef';
const _input = Key('garage_staff_invitation_input');
const _submit = Key('garage_staff_invitation_submit');

void main() {
  testWidgets('acceptance reloads server memberships in the module chooser', (
    tester,
  ) async {
    var joined = false;
    await tester.pumpWidget(
      MaterialApp(
        home: EcosystemGate(
          loadAccess: () async => EcosystemAccess(
            hasFleet: false,
            garages: [
              if (joined)
                const EcosystemDestination(
                  EcosystemModule.mechanic,
                  workspaceId: 'workshop',
                  name: 'QA Workshop',
                ),
            ],
          ),
          destinationBuilder: (_) => const SizedBox.shrink(),
          signOut: () async {},
          acceptInvitationBuilder: (_) => GarageStaffInvitationScreen(
            isCurrentAccount: () => true,
            issue: false,
            submit: (code, _) async {
              expect(code, _code);
              joined = true;
              return 'workshop';
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('ecosystem_accept_staff_invitation')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_input), _code);
    await tester.tap(find.byKey(_submit));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ecosystem_workshop')), findsOneWidget);
  });

  testWidgets('an invitation code from a replaced account is discarded', (
    tester,
  ) async {
    final response = Completer<String>();
    var current = true;
    await tester.pumpWidget(
      MaterialApp(
        home: GarageStaffInvitationScreen(
          isCurrentAccount: () => current,
          issue: true,
          submit: (email, role) {
            expect(email, 'workshop@example.invalid');
            expect(role, 'mechanic');
            return response.future;
          },
        ),
      ),
    );
    await tester.enterText(find.byKey(_input), 'workshop@example.invalid');
    await tester.tap(find.byKey(_submit));
    await tester.pump();
    current = false;
    response.complete(_code);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('garage_staff_issued_code')), findsNothing);
  });
}
