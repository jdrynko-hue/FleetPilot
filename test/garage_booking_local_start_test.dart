import 'dart:io';

import 'package:fleetpilot/garage/booking_local_start.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invalid calendar fields cannot silently normalize', () {
    expect(bookingLocalStart(year: 2026, month: 2, day: 30, hour: 10, minute: 0), isNull);
    expect(bookingLocalStart(year: 2026, month: 11, day: 20, hour: 24, minute: 0), isNull);
    expect(bookingLocalStart(year: 2026, month: 11, day: 20, hour: 10, minute: 60), isNull);
  });

  final london = Platform.environment['TZ'] == 'Europe/London';
  for (final minute in [0, 30, 59]) {
    test('UK missing spring time 01:$minute is rejected', () {
      expect(bookingLocalStart(year: 2026, month: 3, day: 29, hour: 1, minute: minute), isNull);
    }, skip: london ? false : 'Run with TZ=Europe/London');
    test('UK repeated autumn time 01:$minute is rejected', () {
      expect(bookingLocalStart(year: 2026, month: 10, day: 25, hour: 1, minute: minute), isNull);
    }, skip: london ? false : 'Run with TZ=Europe/London');
  }
  const valid = [
    [3, 29, 0, 30, '2026-03-29T00:30:00.000Z'],
    [3, 29, 2, 30, '2026-03-29T01:30:00.000Z'],
    [10, 25, 0, 30, '2026-10-24T23:30:00.000Z'],
    [10, 25, 2, 30, '2026-10-25T02:30:00.000Z'],
    [7, 15, 10, 0, '2026-07-15T09:00:00.000Z'],
    [11, 20, 10, 0, '2026-11-20T10:00:00.000Z'],
  ];
  for (final fixture in valid) {
    test('unambiguous local time resolves to ${fixture[4]}', () {
      final resolved = bookingLocalStart(year: 2026, month: fixture[0] as int,
        day: fixture[1] as int, hour: fixture[2] as int, minute: fixture[3] as int);
      expect(resolved, isNotNull);
      expect(resolved!.toUtc().toIso8601String(), fixture[4]);
    }, skip: london ? false : 'Run with TZ=Europe/London');
  }
}
