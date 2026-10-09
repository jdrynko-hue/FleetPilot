import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/checks/check_logic.dart';

void main() {
  test('Incomplete checks cannot be submitted', () {
    expect(driverCheckResult({'tyres': true, 'brakes': null}), isNull);
    expect(driverCheckResult({}), isNull);
  });
  test('All explicitly inspected items can pass', () {
    expect(driverCheckResult({'tyres': true, 'brakes': true}), 'pass');
  });
  test('Failed items create defect result', () {
    expect(driverCheckResult({'tyres': true, 'brakes': false}), 'defect');
  });
  test('Unsafe result only for a failed item', () {
    expect(driverCheckResult({'tyres': false}, unsafe: true), 'unsafe');
    expect(driverCheckResult({'tyres': true}, unsafe: true), 'pass');
  });
  test('Checklist matches all mandatory database fields', () {
    expect(driverCheckItems.toSet(), {
      'tyres',
      'brakes',
      'lights',
      'mirrors',
      'windscreen',
      'fluids',
      'body',
      'seatbelts',
      'load',
    });
  });
}
