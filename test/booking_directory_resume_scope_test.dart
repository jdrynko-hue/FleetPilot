import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/consumer_booking_repository.dart';
import 'package:fleetpilot/garage/consumer_booking_screen.dart';

import 'booking_directory_navigation_test.dart' as fixture;

const _newShop = GarageBookingWorkshop(
  workspaceId: '00000000-0000-4000-8000-000000000002',
  name: 'Replacement workshop', city: 'Oxford', country: 'GB',
  timeZone: 'Europe/London', services: ['brakes'],
);

Future<String> _submit({required String workspaceId, required String customerName,
    required String vehicleMake, required String vehicleModel,
    required String service, required String concern,
    required DateTime desiredStart, required String requestKey,
    String? registration}) async => throw StateError('Unexpected submission');

void main() {
  setUp(() => AppLocale.language.value = 'en');
  tearDown(() => AppLocale.language.value = 'en');

  for (final oldFails in [false, true]) {
    testWidgets('replacement resume revalidates city and ignores old result error=$oldFails',
        (tester) async {
      final old = Completer<List<GarageBookingWorkshop>>();
      final cities = <String?>[];
      Future<List<GarageBookingWorkshop>> search({String? city}) {
        cities.add(city);
        return cities.length == 1 ? old.future : Future.value([_newShop]);
      }
      Future<void> mount(String city, String id) => tester.pumpWidget(
        MaterialApp(home: GarageBookingSearchScreen(
          initialCity: city, initialWorkshopId: id,
          search: search, submit: _submit,
        )),
      );
      await mount('Luton', fixture.shop.workspaceId);
      await mount(' Oxford ', _newShop.workspaceId);
      await tester.pumpAndSettle();
      if (oldFails) {
        old.completeError(StateError('Private old directory failure'));
      } else {
        old.complete([fixture.shop]);
      }
      await tester.pumpAndSettle();
      expect(cities, ['Luton', 'Oxford']);
      expect(tester.widget<TextField>(find.byKey(const Key('booking_search_city'))).controller!.text, 'Oxford');
      expect(find.text(_newShop.name), findsOneWidget);
      expect(find.text(fixture.shop.name), findsNothing);
      expect(find.byKey(const Key('booking_search_error')), findsNothing);
      expect(find.byType(GarageBookingRequestScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final listed in [false, true]) {
    testWidgets('new directory provider revalidates supplied public intent listed=$listed',
        (tester) async {
      var newSearches = 0;
      String? newCity;
      Future<void> mount(BookingSearch search) => tester.pumpWidget(
        MaterialApp(home: GarageBookingSearchScreen(
          initialCity: 'Luton', initialWorkshopId: fixture.shop.workspaceId,
          search: search, submit: _submit,
        )),
      );
      await mount(({city}) async => [fixture.shop]);
      await tester.pumpAndSettle();
      await mount(({city}) async {
        newSearches++; newCity = city;
        return listed ? [fixture.shop] : [];
      });
      await tester.pumpAndSettle();
      expect(newSearches, 1);
      expect(newCity, 'Luton');
      expect(find.text(fixture.shop.name), listed ? findsOneWidget : findsNothing);
      expect(find.byType(GarageBookingRequestScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('city-only replacement prefills without automatic search', (tester) async {
    var searches = 0;
    Future<List<GarageBookingWorkshop>> search({String? city}) async {
      searches++; return [];
    }
    Future<void> mount(String? city) => tester.pumpWidget(
      MaterialApp(home: GarageBookingSearchScreen(
        initialCity: city, search: search, submit: _submit,
      )),
    );
    await mount('Luton');
    await tester.pumpAndSettle();
    await mount(' Oxford ');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('booking_search_city'))).controller!.text, 'Oxford');
    expect(searches, 0);
    await mount(null);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('booking_search_city'))).controller!.text, isEmpty);
    expect(searches, 0);
  });
}
