import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/auth/portal_entry.dart';
import 'package:fleetpilot/garage/consumer_booking_screen.dart';
import 'package:fleetpilot/garage/consumer_booking_repository.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/ecosystem/ecosystem_access.dart';
import 'package:fleetpilot/ecosystem/ecosystem_gate.dart';

void main() {
  test('URL accepts only known navigation intents', () {
    expect(portalEntryFromUri(Uri.parse('https://example.test/?portal=garage')), PortalEntry.garage);
    expect(portalEntryFromUri(Uri.parse('https://example.test/?portal=admin')), isNull);
  });
  testWidgets('320px chooser exposes three entries and guest workshop search', (tester) async {
    AppLocale.language.value = 'pl';
    addTearDown(() => AppLocale.language.value = 'en');
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    PortalEntry? selected;
    var searched = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Padding(
      padding: const EdgeInsets.all(24), child: PortalEntryPicker(selected: null,
        onSelected: (v) => selected = v, onFindWorkshop: () => searched = true)))));
    await tester.tap(find.byKey(const Key('portal_garage')));
    expect(selected, PortalEntry.garage);
    await tester.tap(find.byKey(const Key('portal_find_workshop')));
    expect(searched, isTrue);
    expect(tester.takeException(), isNull);
  });
  for (final entry in [PortalEntry.customer, PortalEntry.garage]) {
    testWidgets('$entry never sends a new customer to fleet creation', (tester) async {
      EcosystemDestination? opened;
      await tester.pumpWidget(MaterialApp(home: EcosystemGate(
        preferredPortal: entry,
        loadAccess: () async => const EcosystemAccess(hasFleet: false, garages: []),
        signOut: () async {}, destinationBuilder: (d) {
          opened = d;
          return const Scaffold(body: Text('Destination'));
        })));
      await tester.pumpAndSettle();
      if (entry == PortalEntry.customer) {
        expect(opened?.module, EcosystemModule.customer);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(opened?.module, EcosystemModule.customer);
        expect(find.byKey(const Key('ecosystem_customer')), findsOneWidget);
      } else {
        expect(opened, isNull);
      }
    });
  }
  testWidgets('preferred Garage cannot bypass failed membership lookup', (tester) async {
    await tester.pumpWidget(MaterialApp(home: EcosystemGate(
      preferredPortal: PortalEntry.garage,
      loadAccess: () async => throw StateError('private'),
      signOut: () async {}, destinationBuilder: (_) => throw StateError('Must not open'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ecosystem_retry')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('guest discovery requires login before opening a request form', (tester) async {
    var loginRequired = false;
    var submitted = false;
    await tester.pumpWidget(MaterialApp(home: GarageBookingSearchScreen(
      search: ({city}) async => const [GarageBookingWorkshop(
        workspaceId: '00000000-0000-4000-8000-000000000101', name: 'Workshop',
        city: 'Luton', country: 'GB', timeZone: 'Europe/London', services: ['brakes'])],
      submit: ({required workspaceId, required customerName, required vehicleMake,
        required vehicleModel, required service, required concern, required desiredStart,
        required requestKey, registration}) async { submitted = true; return 'unused'; },
      beforeRequest: () async { loginRequired = true; return false; })));
    await tester.tap(find.byKey(const Key('booking_search_submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(OutlinedButton).last);
    await tester.pumpAndSettle();
    expect(loginRequired, isTrue);
    expect(submitted, isFalse);
    expect(find.byType(GarageBookingRequestScreen), findsNothing);
  });

}
