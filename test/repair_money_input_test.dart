import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/formatters.dart';

void main() {
  test('accepts plain decimal amounts without symbols and preserves optional zero', () {
    expect(parseMoneyInput(''), 0);
    expect(parseMoneyInput(' 12,50 '), 12.5);
    expect(parseMoneyInput('12.50'), 12.5);
    expect(parseMoneyInput('.50'), .5);
    expect(parseMoneyInput(',05'), .05);
    expect(parseMoneyInput('9999999999.99'), 9999999999.99);
  });
  for (final input in ['abc', '£12', '1,234.56', '1.234,56', '1 234,56',
    '-1', 'NaN', 'Infinity', '1e3', '12.345', '10000000000', '12,']) {
    test('invalid repair cost is rejected rather than changed to zero: $input', () {
      expect(() => parseMoneyInput(input), throwsFormatException);
      expect(validateMoneyInput(input, locale: 'pl'), isNotNull);
    });
  }
  testWidgets('invalid cost prevents form submission and can be corrected', (tester) async {
    final form = GlobalKey<FormState>();
    var writes = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Form(key: form,
      child: Column(children: [
        TextFormField(validator: (value) => validateMoneyInput(value, locale: 'pl')),
        FilledButton(onPressed: () { if (form.currentState!.validate()) writes++; }, child: const Text('Save')),
      ])))));
    await tester.enterText(find.byType(TextFormField), 'NaN');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(writes, 0);
    await tester.enterText(find.byType(TextFormField), '125,50');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(writes, 1);
  });
}
