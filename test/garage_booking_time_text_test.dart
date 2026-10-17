import 'dart:io';

import 'package:fleetpilot/garage/booking_time_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // CI explicitly sets Europe/London so these assertions exercise both
  // winter/summer and the two ambiguous 01:30 clock times in October.
  final london = Platform.environment['TZ'] == 'Europe/London';
  const fixtures = {
    '2026-01-15T10:00:00Z': '2026-01-15 10:00 (GMT)',
    '2026-07-15T10:00:00Z': '2026-07-15 11:00 (BST)',
    '2026-03-29T00:30:00Z': '2026-03-29 00:30 (GMT)',
    '2026-03-29T01:30:00Z': '2026-03-29 02:30 (BST)',
    '2026-10-25T00:30:00Z': '2026-10-25 01:30 (BST)',
    '2026-10-25T01:30:00Z': '2026-10-25 01:30 (GMT)',
  };
  for (final fixture in fixtures.entries) {
    test('booking local clock and zone agree for ${fixture.key}', () {
      expect(bookingLocalTimeLabel(DateTime.parse(fixture.key)), fixture.value);
    }, skip: london ? false : 'Run with TZ=Europe/London (dedicated CI step)');
  }
}
