import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/garage/quote_order_repository.dart';
import 'package:fleetpilot/garage/workshop_quotes_screen.dart';
import 'package:fleetpilot/garage/workshop_quote_publisher.dart';

const id = '00000000-0000-4000-8000-000000000001';
void main() {
  test('quote order listing rejects unknown and unscoped values', () {
    expect(GarageQuoteOrderRepository.parseOrders([
      {'id':id,'complaint':'Brakes','status':'diagnosing'}
    ]).single.canQuote, isTrue);
    expect(() => GarageQuoteOrderRepository.parseOrders([
      {'id':'bad','complaint':'Brakes','status':'ready'}
    ]), throwsFormatException);
    expect(() => GarageQuoteOrderRepository.parseOrders([
      {'id':id,'complaint':'Brakes','status':'invented'}
    ]), throwsFormatException);
  });
  test('money is parsed as exact integer minor units', () {
    expect(parseGarageMajorAmount('GBP','12.50'),1250);
    expect(parseGarageMajorAmount('PLN','1,05'),105);
    expect(parseGarageMajorAmount('JPY','450'),450);
    expect(parseGarageMajorAmount('KWD','1.205'),1205);
    expect(() => parseGarageMajorAmount('JPY','1.01'),throwsFormatException);
    expect(() => parseGarageMajorAmount('GBP','1.001'),throwsFormatException);
    expect(() => parseGarageMajorAmount('GBP','-1'),throwsFormatException);
  });
  testWidgets('publishing requires confirmation and locks completed draft',
      (tester) async {
    var calls=0;
    List<GarageQuoteDraftLine> saved=[];
    await tester.pumpWidget(MaterialApp(home:GarageQuoteEditorScreen(
      order:const GarageQuoteOrder(id:id,complaint:'Brakes',status:'diagnosing'),
      loadCurrency:() async =>
        const GarageQuoteCurrencySelection('GBP',locked:false),
      publish:(currency,lines) async {
        expect(currency,'GBP');calls++;saved=lines;return 2;
      },
    )));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('quote_description_0')),'Pads');
    await tester.enterText(find.byKey(const Key('quote_quantity_0')),'2');
    await tester.enterText(find.byKey(const Key('quote_unit_0')),'20.25');
    await tester.enterText(find.byKey(const Key('quote_tax_0')),'4.50');
    await tester.ensureVisible(find.byKey(const Key('quote_publish')));
    await tester.tap(find.byKey(const Key('quote_publish')));
    await tester.pumpAndSettle();
    expect(calls,0);
    await tester.tap(find.byKey(const Key('garage_editor_confirm')));
    await tester.pumpAndSettle();
    expect(calls,1);
    expect(saved.single.unitPriceMinor,2025);
    expect(saved.single.taxMinor,450);
    expect(find.byKey(const Key('quote_editor_success')),findsOneWidget);
    expect(find.byKey(const Key('quote_publish')),findsNothing);
  });
  testWidgets('unconfirmed server result prevents duplicate publication',
      (tester) async {
    var calls=0;
    await tester.pumpWidget(MaterialApp(home:GarageQuoteEditorScreen(
      order:const GarageQuoteOrder(id:id,complaint:'Clutch',status:'awaiting_approval'),
      loadCurrency:() async =>
        const GarageQuoteCurrencySelection('GBP',locked:true),
      publish:(_,__) async { calls++;throw StateError('unknown'); },
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('garage_quote_currency')),findsNothing);
    await tester.enterText(find.byKey(const Key('quote_description_0')),'Clutch');
    await tester.enterText(find.byKey(const Key('quote_unit_0')),'50');
    await tester.ensureVisible(find.byKey(const Key('quote_publish')));
    await tester.tap(find.byKey(const Key('quote_publish')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('garage_editor_confirm')));
    await tester.pumpAndSettle();
    expect(calls,1);
    expect(find.byKey(const Key('quote_editor_error')),findsOneWidget);
    expect(find.byKey(const Key('quote_publish')),findsNothing);
  });
}
