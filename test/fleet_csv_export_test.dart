import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/fleet_csv_export.dart';

void main() {
  test('Quotes CSV separators, quotes and line breaks', () {
    expect(escapeFleetCsvValue('A,B'), '"A,B"');
    expect(escapeFleetCsvValue('He said "yes"'), '"He said ""yes"""');
    expect(escapeFleetCsvValue('Line 1\nLine 2'), '"Line 1\nLine 2"');
  });

  test('Neutralizes spreadsheet formula injection', () {
    expect(escapeFleetCsvValue('=1+1'), "'=1+1");
    expect(escapeFleetCsvValue('  +SUM(A1)'), "'+SUM(A1)");
    expect(escapeFleetCsvValue('@IMPORT'), "'@IMPORT");
    expect(escapeFleetCsvValue('-42'), "'-42");
    expect(escapeFleetCsvValue(-42), '-42');
  });

  test('CSV is UTF-8 Excel-friendly and CRLF delimited', () {
    final csv = encodeFleetCsv([
      ['Name', 'Cost'],
      ['Łukasz', 12.5],
    ]);
    expect(csv.startsWith('\uFEFF'), isTrue);
    expect(csv, contains('Łukasz,12.5\r\n'));
  });
}
