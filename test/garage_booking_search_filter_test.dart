import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/auth/billing_markets.dart';
import 'package:fleetpilot/garage/booking_status_text.dart';
import 'package:fleetpilot/garage/consumer_booking_repository.dart';
import 'package:fleetpilot/garage/consumer_booking_screen.dart';
import 'package:fleetpilot/garage/garage_ui_text.dart';
import 'garage_booking_screens_test.dart' as fixture;

const tyreShop = GarageBookingWorkshop(
  workspaceId: '00000000-0000-4000-8000-000000000102',
  name: 'Tyre Workshop', city: 'Dunstable', country: 'GB',
  timeZone: 'Europe/London', services: ['tyres'],
);
const polishShop = GarageBookingWorkshop(
  workspaceId: '00000000-0000-4000-8000-000000000103',
  name: 'Polish Workshop', city: 'Dunstable', country: 'PL',
  timeZone: 'Europe/Warsaw', services: ['brakes'],
);
final BookingSubmit submit = ({required workspaceId, required customerName,
  required vehicleMake, required vehicleModel, required service, required concern,
  required desiredStart, required requestKey, registration}) async => fixture.bookingId;

Future<void> selectService(WidgetTester tester, String code) async {
  await tester.ensureVisible(find.byKey(const Key('booking_search_service')));
  await tester.tap(find.byKey(const Key('booking_search_service')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(code.isEmpty ? GarageUiText.get('bookingSearchAllServices')
      : bookingServiceLabel(code)).last);
  await tester.pumpAndSettle();
}

Future<void> search(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('booking_search_submit')));
  await tester.tap(find.byKey(const Key('booking_search_submit')));
  await tester.pumpAndSettle();
}

Future<void> selectCountry(WidgetTester tester, String code) async {
  final picker = find.byKey(const Key('booking_search_country'));
  await tester.ensureVisible(picker);
  await tester.tap(picker); await tester.pumpAndSettle();
  await tester.tap(find.text(code.isEmpty ? GarageUiText.get('bookingSearchAllCountries')
      : '${fleetCountryName(code, locale: AppLocale.language.value)} ($code)').last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => AppLocale.language.value = 'en');
  tearDown(() => AppLocale.language.value = 'en');

  testWidgets('country and service filters combine locally and can restore results', (tester) async {
    var calls = 0;
    await fixture.render(tester, GarageBookingSearchScreen(
      search: ({city}) async { calls++; return [fixture.shop, tyreShop, polishShop]; },
      submit: submit), width: 320);
    expect(find.byKey(const Key('booking_search_country')), findsNothing);
    await search(tester);
    await selectCountry(tester, 'PL');
    expect(find.byKey(Key('booking_shop_${polishShop.workspaceId}')), findsOneWidget);
    expect(find.byKey(Key('booking_shop_${fixture.shop.workspaceId}')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('booking_search_count'))).data,
      GarageUiText.format('bookingSearchCount', {'count': 1}));
    await selectService(tester, 'tyres');
    expect(find.byKey(const Key('booking_search_no_filters')), findsOneWidget);
    expect(find.byType(Card), findsNothing);
    await selectCountry(tester, 'GB');
    expect(find.byKey(Key('booking_shop_${tyreShop.workspaceId}')), findsOneWidget);
    await selectCountry(tester, '');
    await selectService(tester, '');
    // ListView virtualizes off-screen cards; assert the complete filtered count.
    expect(tester.widget<Text>(find.byKey(const Key('booking_search_count'))).data,
      GarageUiText.format('bookingSearchCount', {'count': 3}));
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new result countries reset an unavailable selected country', (tester) async {
    var calls = 0;
    await fixture.render(tester, GarageBookingSearchScreen(
      search: ({city}) async => ++calls == 1 ? [polishShop] : [tyreShop], submit: submit));
    await search(tester); await selectCountry(tester, 'PL');
    await search(tester);
    expect(find.text(GarageUiText.get('bookingSearchAllCountries')), findsOneWidget);
    expect(find.byKey(Key('booking_shop_${tyreShop.workspaceId}')), findsOneWidget);
    expect(find.byKey(const Key('booking_search_no_filters')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local filter narrows loaded results and can restore all without a new request', (tester) async {
    var calls = 0;
    await fixture.render(tester, GarageBookingSearchScreen(
      search: ({city}) async { calls++; return [fixture.shop, tyreShop]; },
      submit: submit,
    ), width: 320);
    await search(tester);
    expect(find.byKey(const Key('booking_search_limit_hint')), findsOneWidget);
    await selectService(tester, 'tyres');
    expect(find.byKey(Key('booking_shop_${fixture.shop.workspaceId}')), findsNothing);
    expect(find.byKey(Key('booking_shop_${tyreShop.workspaceId}')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('booking_search_count'))).data,
      GarageUiText.format('bookingSearchCount', {'count': 1}));
    await selectService(tester, 'electrical');
    expect(find.byKey(const Key('booking_search_no_service')), findsOneWidget);
    expect(find.byType(Card), findsNothing);
    await selectService(tester, '');
    expect(find.byKey(Key('booking_shop_${fixture.shop.workspaceId}')), findsOneWidget);
    expect(calls, 1);
    expect(find.byKey(const Key('booking_not_guaranteed')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('directory scope change resets filter and city and discards a late response', (tester) async {
    final pending = Completer<List<GarageBookingWorkshop>>();
    var calls = 0;
    final BookingSearch oldSearch = ({city}) async {
      if (++calls == 1) return [fixture.shop];
      return pending.future;
    };
    await fixture.render(tester, GarageBookingSearchScreen(search: oldSearch, submit: submit));
    await search(tester);
    await selectCountry(tester, 'GB');
    await selectService(tester, 'brakes');
    await tester.enterText(find.byKey(const Key('booking_search_city')), 'Old city');
    await tester.tap(find.byKey(const Key('booking_search_submit')));
    await tester.pump();
    expect(tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('booking_search_service'))).onChanged, isNull);
    await tester.pumpWidget(MaterialApp(home: GarageBookingSearchScreen(
      search: ({city}) async => [tyreShop], submit: submit)));
    pending.complete([fixture.shop]);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('booking_search_city'))).controller!.text, isEmpty);
    expect(find.byKey(Key('booking_shop_${fixture.shop.workspaceId}')), findsNothing);
    expect(find.byKey(const Key('booking_search_count')), findsNothing);
    await search(tester);
    expect(find.byKey(Key('booking_shop_${tyreShop.workspaceId}')), findsOneWidget);
    expect(find.text(GarageUiText.get('bookingSearchAllCountries')), findsOneWidget);
    expect(find.byKey(const Key('booking_search_no_service')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed search removes results and match counts without an empty-service claim', (tester) async {
    var fail = false;
    await fixture.render(tester, GarageBookingSearchScreen(
      search: ({city}) async { if (fail) throw StateError('offline'); return [fixture.shop]; },
      submit: submit));
    await search(tester);
    await selectService(tester, 'brakes');
    fail = true;
    await search(tester);
    expect(find.byKey(const Key('booking_search_error')), findsOneWidget);
    expect(find.byKey(const Key('booking_search_count')), findsNothing);
    expect(find.byKey(const Key('booking_search_no_service')), findsNothing);
    expect(find.byKey(Key('booking_shop_${fixture.shop.workspaceId}')), findsNothing);
  });

  testWidgets('invalid city clears previous results without another API call', (tester) async {
    var calls = 0;
    await fixture.render(tester, GarageBookingSearchScreen(
      search: ({city}) async { calls++; return [fixture.shop]; }, submit: submit));
    await search(tester);
    await tester.enterText(find.byKey(const Key('booking_search_city')), 'A');
    await search(tester);
    expect(calls, 1);
    expect(find.byKey(Key('booking_shop_${fixture.shop.workspaceId}')), findsNothing);
    expect(find.byKey(const Key('booking_search_count')), findsNothing);
    expect(find.byKey(const Key('booking_search_error')), findsOneWidget);
  });

  for (final locale in supportedLanguages) {
    testWidgets('search/filter and limited-result copy render at 320px in $locale', (tester) async {
      AppLocale.language.value = locale;
      await fixture.render(tester, GarageBookingSearchScreen(
        search: ({city}) async => [fixture.shop], submit: submit), width: 320);
      expect(find.text(GarageUiText.get('bookingSearchAction')), findsOneWidget);
      await search(tester);
      expect(find.text(GarageUiText.get('bookingSearchAllCountries')), findsOneWidget);
      await selectCountry(tester, 'GB');
      expect(tester.widget<Text>(find.byKey(const Key('booking_search_limit_hint'))).data,
        contains('30'));
      await selectService(tester, 'tyres');
      expect(find.text(GarageUiText.get('bookingSearchNoFilters')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
