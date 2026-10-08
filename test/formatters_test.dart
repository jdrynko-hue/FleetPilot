import 'package:fleetpilot/core/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats mileage with separators', () {
    expect(formatMileage(123456), '123,456');
  });

  test('parses formatted mileage input', () {
    expect(parseInt('123,456'), 123456);
  });

  test('formats GBP', () {
    expect(formatMoney(123.4), '£123.40');
  });

  test('parses comma decimal money input', () {
    expect(parseMoneyInput('12,50'), 12.5);
  });
}
