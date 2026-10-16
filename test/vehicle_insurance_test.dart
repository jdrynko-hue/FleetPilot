import 'dart:convert';

import 'package:fleetpilot/core/formatters.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/data/fleet_repository.dart';
import 'package:fleetpilot/data/models.dart';
import 'package:fleetpilot/vehicles/insurance_expiry.dart';
import 'package:fleetpilot/vehicles/vehicle_list_tile.dart';
import 'package:fleetpilot/vehicles/vehicles_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  tearDown(() => AppLocale.language.value = 'en');

  test('insurance window includes day 30, today and overdue, not missing dates', () {
    final today = DateTime(2026, 10, 16, 23, 59);
    expect(insuranceNeedsAttention(null, today), isFalse);
    for (final days in [-365, -1, 0, 1, 7, 14, 30, 31]) {
      final expiry = DateTime(2026, 10, 16 + days);
      expect(calendarDaysUntil(expiry, today), days);
      expect(insuranceNeedsAttention(expiry, today), days <= 30);
    }
    // Date-only arithmetic stays correct across the UK spring clock change.
    expect(calendarDaysUntil(DateTime(2026, 3, 30), DateTime(2026, 3, 28, 23)), 2);
    expect(calendarDaysUntil(DateTime(2027, 1, 1), DateTime(2026, 12, 31)), 1);
  });

  testWidgets('expiry text distinguishes missing, upcoming, today and expired', (tester) async {
    final today = DateTime(2026, 10, 16);
    for (final days in <int?>[null, -1, 0, 7, 14, 30, 31]) {
      final date = days == null ? null : DateTime(2026, 10, 16 + days);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: InsuranceExpiry(date: date, today: today)),
      ));
      final text = tester.widget<Text>(find.descendant(
        of: find.byType(InsuranceExpiry), matching: find.byType(Text),
      )).data!;
      if (days == null) {
        expect(text, contains('Date not set'));
      } else {
        expect(text, contains(formatDate(date)));
        if (days < 0) expect(text, contains('Overdue'));
        if (days == 0) expect(text, contains('Due today'));
        if (days > 0 && days <= 30) expect(text, contains('$days days left'));
        if (days > 30) expect(text, isNot(contains('days left')));
      }
    }
  });

  for (final language in supportedLanguages) {
    testWidgets('insurance row fits a phone with large text in $language', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppLocale.language.value = language;
      final vehicle = Vehicle.fromJson({
        'id': 'car', 'company_id': 'fleet', 'registration': 'AB26 TEST',
        'status': 'available', 'mileage': 125000, 'make': 'Mercedes-Benz',
        'model': 'Sprinter', 'drivers': {'name': 'Alex Long Driver Name'},
        'insurance_expiry_date': DateTime.now().toIso8601String().substring(0, 10),
      });
      var opened = 0;
      var edited = 0;
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(body: VehicleListTile(
          vehicle: vehicle,
          onOpen: () => opened++,
          onEdit: () => edited++,
        )),
      ));
      expect(tester.takeException(), isNull);
      expect(find.textContaining(tr('insurance_expiry')), findsOneWidget);
      expect(find.textContaining(tr('notification_due_today')), findsOneWidget);
      expect(tr('insurance_date_missing'), isNot('insurance_date_missing'));
      expect(trf('insurance_days_remaining', {'days': 14}), isNot(contains('{days}')));
      await tester.tap(find.byIcon(Icons.edit_outlined));
      expect(edited, 1);
      expect(opened, 0);
      await tester.tap(find.text('AB26 TEST'));
      expect(opened, 1);
    });
  }

  testWidgets('Vehicles filters real repository results and keeps fleet scope', (tester) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final today = DateTime.now();
    final transport = MockClient((request) async {
      expect(request.url.path, '/rest/v1/vehicles');
      expect(request.url.queryParameters['company_id'], 'eq.fleet-a');
      expect(request.url.queryParameters['is_active'], 'eq.true');
      return http.Response(jsonEncode([
        for (final days in <int?>[-1, 0, 30, 31, null])
          {
            'id': 'car-$days', 'company_id': 'fleet-a',
            'registration': 'CAR $days', 'mileage': 1000, 'status': 'available',
            'insurance_expiry_date': days == null ? null :
                DateTime(today.year, today.month, today.day + days).toIso8601String().substring(0, 10),
          },
      ]), 200, headers: {'content-type': 'application/json'});
    });
    final client = SupabaseClient('https://fleet-test.invalid', 'test-anon', httpClient: transport);
    addTearDown(client.dispose);
    addTearDown(transport.close);
    await tester.pumpWidget(MaterialApp(home: VehiclesScreen(
      company: CompanyMembership(companyId: 'fleet-a', companyName: 'Fleet A', role: 'viewer', currency: 'GBP'),
      canManage: false, refreshToken: 0, onDataChanged: () {},
      repository: FleetRepository(client),
    )));
    await tester.pumpAndSettle();
    expect(find.byType(VehicleListTile), findsNWidgets(5));
    expect(find.textContaining('Date not set'), findsOneWidget);
    expect(find.text('Insurance: within 30 days / overdue (3)'), findsOneWidget);
    await tester.tap(find.byType(FilterChip));
    await tester.pumpAndSettle();
    expect(find.byType(VehicleListTile), findsNWidgets(3));
    expect(find.text('CAR 31'), findsNothing);
    expect(find.text('CAR null'), findsNothing);
    await tester.enterText(find.byType(TextField), 'CAR 31');
    await tester.pumpAndSettle();
    expect(find.text('No matching vehicles'), findsOneWidget);
    await tester.tap(find.byType(FilterChip));
    await tester.pumpAndSettle();
    expect(find.text('CAR 31'), findsOneWidget);
    expect(find.byType(VehicleListTile), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
