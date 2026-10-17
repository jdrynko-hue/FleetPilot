import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/auth/billing_markets.dart';
import 'package:fleetpilot/ecosystem/ecosystem_access.dart';
import 'package:fleetpilot/garage/booking_profile_screen.dart';
import 'package:fleetpilot/garage/consumer_booking_repository.dart';
import 'package:fleetpilot/garage/workshop_time_zone.dart';

void main() {
  test('all supported workshop countries have an editable IANA suggestion', () {
    expect(workshopTimeZoneSuggestions.keys.toSet(), supportedFleetCountries.keys.toSet());
    expect(suggestedWorkshopTimeZone(' pl '), 'Europe/Warsaw');
    expect(suggestedWorkshopTimeZone('GB'), 'Europe/London');
    expect(suggestedWorkshopTimeZone('ES'), 'Europe/Madrid');
    expect(suggestedWorkshopTimeZone('PT'), 'Europe/Lisbon');
    expect(suggestedWorkshopTimeZone(null), 'Europe/London');
    expect(suggestedWorkshopTimeZone('unknown'), 'Europe/London');
  });
  for (final country in ['PL', 'GB', 'DE']) {
    test('membership carries workshop country without changing role permissions: $country', () async {
      const user = '00000000-0000-4000-8000-000000000001';
      const workspace = '00000000-0000-4000-8000-000000000002';
      for (final role in ['owner', 'service_adviser', 'mechanic']) {
        final access = await EcosystemAccessRepository(currentUserId: () => user,
          fleetRows: (_) async => [], garageRows: (_) async => [{
            'user_id': user, 'workspace_id': workspace, 'role': role,
            'garage_workspaces': {'name': 'Synthetic workshop', 'country': country},
          }]).load();
        expect(access.garages.single.country, country);
        expect(access.garages.single.canConfigure, role == 'owner');
      }
    });
    testWidgets('new $country profile uses country suggestion without saving', (tester) async {
      var writes = 0;
      await tester.pumpWidget(MaterialApp(home: GarageBookingProfileScreen(
        initialTimeZone: suggestedWorkshopTimeZone(country), load: () async => null,
        save: ({required city, required timeZone, required services, required durationMinutes, required listed}) async {
          writes++; return true;
        })));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byKey(const Key('booking_profile_zone')));
      expect(field.controller!.text, suggestedWorkshopTimeZone(country));
      await tester.enterText(find.byKey(const Key('booking_profile_zone')), 'Atlantic/Canary');
      expect(field.controller!.text, 'Atlantic/Canary');
      expect(writes, 0);
    });
  }
  testWidgets('saved regional time zone overrides the country suggestion', (tester) async {
    await tester.pumpWidget(MaterialApp(home: GarageBookingProfileScreen(
      initialTimeZone: suggestedWorkshopTimeZone('ES'),
      load: () async => const GarageBookingProfile(
        workspaceId: '00000000-0000-4000-8000-000000000001', city: 'Las Palmas',
        timeZone: 'Atlantic/Canary', services: ['brakes'], durationMinutes: 60, listed: false),
      save: ({required city, required timeZone, required services, required durationMinutes, required listed}) async => true)));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('booking_profile_zone'))).controller!.text,
      'Atlantic/Canary');
    final save = find.byKey(const Key('booking_profile_save'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AlertDialog),
      matching: find.textContaining('Atlantic/Canary')), findsOneWidget);
  });
}
