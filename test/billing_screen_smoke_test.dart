import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/company/billing_screen.dart';

void main() {
  test('Flotaryx subscription screen can be loaded', () {
    expect(BillingScreen, isNotNull);
  });

  final now = DateTime.utc(2026, 11, 26);

  FleetTrialCheckoutState trialState({
    bool qaSandbox = true,
    String? billingProvider = 'manual',
    String status = 'trialing',
    DateTime? endsAt,
  }) => fleetTrialCheckoutState(
    qaSandbox: qaSandbox,
    billingProvider: billingProvider,
    status: status,
    trialEndsAt: endsAt,
    now: now,
  );

  test('only a manual trial on the QA Sandbox is subject to the cutoff', () {
    expect(trialState(qaSandbox: false), FleetTrialCheckoutState.notApplicable);
    expect(
      trialState(billingProvider: 'stripe'),
      FleetTrialCheckoutState.notApplicable,
    );
    expect(
      trialState(billingProvider: null),
      FleetTrialCheckoutState.notApplicable,
    );
    expect(trialState(status: 'active'), FleetTrialCheckoutState.notApplicable);
    expect(trialState(status: 'canceled'), FleetTrialCheckoutState.notApplicable);
  });

  test('a QA manual trial without a stored end date fails closed', () {
    expect(trialState(), FleetTrialCheckoutState.dateUnavailable);
  });

  test('Checkout opens at the stored trial end, including its timezone', () {
    expect(
      trialState(endsAt: now.add(const Duration(milliseconds: 1))),
      FleetTrialCheckoutState.active,
    );
    expect(
      trialState(endsAt: DateTime.parse('2026-11-26T01:00:00+01:00')),
      FleetTrialCheckoutState.ended,
    );
    expect(
      trialState(endsAt: now.subtract(const Duration(milliseconds: 1))),
      FleetTrialCheckoutState.ended,
    );
  });
}
