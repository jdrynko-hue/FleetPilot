import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/app.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/core/material_localization.dart';
import 'package:fleetpilot/garage/consumer_booking_screen.dart';

Future<void> renderPicker(WidgetTester tester, String language,
    void Function(DateTime?) completed) async {
  tester.view.physicalSize = const Size(320, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    locale: materialLocale(language),
    supportedLocales: supportedMaterialLocales,
    localizationsDelegates: materialLocalizationDelegates,
    home: Scaffold(body: Builder(builder: (context) => FilledButton(
      onPressed: () async => completed(await pickBookingTime(context)),
      child: const Text('Open picker'))))));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open picker'));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => AppLocale.language.value = 'en');
  test('unsupported language uses English framework controls', () {
    expect(materialLocale('invalid'), const Locale('en'));
    expect(supportedMaterialLocales.map((l) => l.languageCode), supportedLanguages);
  });
  for (final locale in supportedLanguages) {
    testWidgets('production app wires framework language $locale', (tester) async {
      AppLocale.language.value = locale;
      await tester.pumpWidget(const FleetPilotApp());
      await tester.pumpAndSettle();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.locale, Locale(locale));
      expect(app.supportedLocales, supportedMaterialLocales);
      expect(app.localizationsDelegates, materialLocalizationDelegates);
      final context = tester.element(find.byType(Scaffold).first);
      expect(Localizations.localeOf(context).languageCode, locale);
      expect(tester.takeException(), isNull);
    });
    for (final cancelStage in ['date', 'time']) {
      testWidgets('$locale cancel $cancelStage returns no booking time at 320px', (tester) async {
        AppLocale.language.value = locale;
        var calls = 0;
        DateTime? result;
        await renderPicker(tester, locale, (value) { calls++; result = value; });
        final dateContext = tester.element(find.byType(DatePickerDialog));
        expect(Localizations.localeOf(dateContext).languageCode, locale);
        final dateText = MaterialLocalizations.of(dateContext);
        await tester.tap(find.text(cancelStage == 'date'
          ? dateText.cancelButtonLabel : dateText.okButtonLabel));
        await tester.pumpAndSettle();
        if (cancelStage == 'time') {
          final context = tester.element(find.byType(TimePickerDialog));
          expect(Localizations.localeOf(context).languageCode, locale);
          await tester.tap(find.text(MaterialLocalizations.of(context).cancelButtonLabel));
          await tester.pumpAndSettle();
        }
        expect(calls, 1);
        expect(result, isNull);
        expect(find.byType(DatePickerDialog), findsNothing);
        expect(find.byType(TimePickerDialog), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('$locale confirms device-local date and time at 320px', (tester) async {
      AppLocale.language.value = locale;
      DateTime? result;
      var calls = 0;
      await renderPicker(tester, locale, (value) { calls++; result = value; });
      final day = tester.widget<DatePickerDialog>(find.byType(DatePickerDialog)).initialDate!;
      final dateContext = tester.element(find.byType(DatePickerDialog));
      await tester.tap(find.text(MaterialLocalizations.of(dateContext).okButtonLabel));
      await tester.pumpAndSettle();
      final timeContext = tester.element(find.byType(TimePickerDialog));
      expect(Localizations.localeOf(timeContext).languageCode, locale);
      await tester.tap(find.text(MaterialLocalizations.of(timeContext).okButtonLabel));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(result, isNotNull);
      expect([result!.year, result!.month, result!.day, result!.hour, result!.minute],
        [day.year, day.month, day.day, 10, 0]);
      expect(tester.takeException(), isNull);
    });
  }
}
