import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/auth/portal_entry.dart';
import 'package:fleetpilot/ecosystem/ecosystem_access.dart';
import 'package:fleetpilot/ecosystem/ecosystem_gate.dart';

void main() {
  testWidgets('new Garage account opens workshop setup once and may go back', (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(home: EcosystemGate(
      preferredPortal: PortalEntry.garage,
      loadAccess: () async => const EcosystemAccess(hasFleet: false, garages: []),
      signOut: () async {}, destinationBuilder: (_) => throw StateError('No membership'),
      createWorkshopBuilder: (_) {
        opened++;
        return Scaffold(appBar: AppBar(title: const Text('Workshop setup')));
      })));
    await tester.pumpAndSettle();
    expect(find.text('Workshop setup'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Workshop setup'), findsNothing);
    expect(opened, 1);
    expect(find.byKey(const Key('ecosystem_create_workshop')), findsOneWidget);
  });
  testWidgets('failed lookup does not assume the account has no workshop', (tester) async {
    await tester.pumpWidget(MaterialApp(home: EcosystemGate(
      preferredPortal: PortalEntry.garage,
      loadAccess: () async => throw StateError('transport failure'),
      signOut: () async {}, destinationBuilder: (_) => const SizedBox(),
      createWorkshopBuilder: (_) => throw StateError('Must not open setup'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ecosystem_retry')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('customer entry never opens business setup', (tester) async {
    await tester.pumpWidget(MaterialApp(home: EcosystemGate(
      preferredPortal: PortalEntry.customer,
      loadAccess: () async => const EcosystemAccess(hasFleet: false, garages: []),
      signOut: () async {},
      destinationBuilder: (d) {
        expect(d.module, EcosystemModule.customer);
        return const Scaffold(body: Text('Customer bookings'));
      }, createWorkshopBuilder: (_) => throw StateError('Customer is not a business'))));
    await tester.pumpAndSettle();
    expect(find.text('Customer bookings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('returning from a module releases the navigation guard', (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(home: EcosystemGate(
      loadAccess: () async => const EcosystemAccess(hasFleet: false, garages: []),
      signOut: () async {}, destinationBuilder: (_) {
        opened++;
        return Scaffold(appBar: AppBar(title: const Text('Bookings')));
      })));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ecosystem_customer')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ecosystem_customer')));
    await tester.pumpAndSettle();
    expect(opened, 2);
    expect(find.text('Bookings'), findsOneWidget);
  });

}
