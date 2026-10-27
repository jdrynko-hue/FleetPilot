import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/vehicles/smart_maintenance.dart';

void main() {
  test('UK odometer stays in miles, 10k km converts to 6214 mi', () {
    expect(toMiles(10000, MaintenanceUnit.km), 6214);
    expect(toMiles(10000, MaintenanceUnit.mi), 10000);
    expect(fromMiles(6214, MaintenanceUnit.km), 10000);
    expect(nextServiceMiles(
      lastServiceMiles: 84500, intervalDistance: 10000,
      unit: MaintenanceUnit.km), 90714);
    expect(nextServiceMiles(
      lastServiceMiles: 84500, intervalDistance: 10000,
      unit: MaintenanceUnit.mi), 94500);
  });

  test('invalid intervals are not accepted', () {
    expect(() => nextServiceMiles(
        lastServiceMiles: 1, intervalDistance: 0,
        unit: MaintenanceUnit.km), throwsArgumentError);
    expect(() => toMiles(-1, MaintenanceUnit.mi), throwsArgumentError);
  });

  test('service at end of January rounds to end of February', () {
    expect(addCalendarMonths(DateTime.utc(2027, 1, 31), 1),
        DateTime.utc(2027, 2, 28));
    expect(addCalendarMonths(DateTime.utc(2028, 1, 31), 1),
        DateTime.utc(2028, 2, 29));
  });

  MaintenancePlan plan({int? dueMiles = 10000, DateTime? dueDate,
      bool active = true}) => MaintenancePlan(
    id: 'fixture', companyId: 'fleet', vehicleId: 'van',
    kind: MaintenanceKind.oil, unit: MaintenanceUnit.mi,
    lastServiceMiles: 5000, lastServiceDate: DateTime.utc(2026, 1, 1),
    nextDueMiles: dueMiles, nextDueDate: dueDate,
    intervalDistance: 5000, intervalMonths: 12, active: active,
  );

  test('mileage reminders distinguish upcoming, due and overdue', () {
    final today = DateTime.utc(2026, 3, 1);
    expect(plan().attention(8000, today), MaintenanceAttention.normal);
    expect(plan().attention(9400, today), MaintenanceAttention.upcoming);
    expect(plan().attention(10000, today), MaintenanceAttention.due);
    expect(plan().attention(10100, today), MaintenanceAttention.overdue);
  });

  test('calendar reminder is checked regardless of remaining mileage', () {
    final today = DateTime.utc(2026, 10, 19);
    expect(plan(dueMiles: 50000, dueDate: DateTime.utc(2026, 11, 5))
        .attention(0, today), MaintenanceAttention.upcoming);
    expect(plan(dueMiles: null, dueDate: DateTime.utc(2026, 10, 19))
        .attention(0, today), MaintenanceAttention.due);
    expect(plan(dueMiles: null, dueDate: DateTime.utc(2026, 10, 18))
        .attention(0, today), MaintenanceAttention.overdue);
    expect(plan(active: false).attention(10000, today),
        MaintenanceAttention.unscheduled);
  });

  test('forecast uses monotonic readings and returns an indicative date', () {
    final predicted = estimateDueDate(
      remainingMiles: 1800,
      older: MaintenanceOdometerReading(10000, DateTime.utc(2026, 10, 1)),
      newer: MaintenanceOdometerReading(11200, DateTime.utc(2026, 10, 15)),
    );
    expect(predicted, DateTime.utc(2026, 11, 5));
    expect(estimateDueDate(
      remainingMiles: 1800,
      older: MaintenanceOdometerReading(12000, DateTime.utc(2026, 10, 1)),
      newer: MaintenanceOdometerReading(11200, DateTime.utc(2026, 10, 15)),
    ), isNull);
  });

  test('maintenance codes include every planned vehicle category', () {
    expect(maintenanceCodes.length, 10);
    expect(maintenanceCodes[MaintenanceKind.oil], 'oil');
    expect(parseMaintenanceKind('road_tax'), MaintenanceKind.roadTax);
  });
}
