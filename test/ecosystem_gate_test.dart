import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/ecosystem/ecosystem_access.dart';
import 'package:fleetpilot/ecosystem/ecosystem_gate.dart';

void main() {
  setUp(() => AppLocale.language.value='en');
  testWidgets('customer enters bookings without creating a fleet', (tester) async {
    EcosystemDestination? opened;
    await tester.pumpWidget(MaterialApp(home: EcosystemGate(
      loadAccess: () async => const EcosystemAccess(hasFleet:false,garages:[]),
      signOut: () async {}, destinationBuilder: (d) {
        opened=d;return const Scaffold(body:Text('Actual booking destination'));
      })));
    await tester.pumpAndSettle();
    expect(opened,isNull);expect(find.text('Create a fleet'),findsOneWidget);
    await tester.tap(find.byKey(const Key('ecosystem_customer')));
    await tester.pumpAndSettle();expect(opened!.module,EcosystemModule.customer);
    expect(find.text('Actual booking destination'),findsOneWidget);
  });
  testWidgets('failed refresh hides previous staff access and private errors', (tester) async {
    var fail=false;
    await tester.pumpWidget(MaterialApp(home:EcosystemGate(
      loadAccess: () async {
        if(fail)throw StateError('PRIVATE DATABASE DETAIL');
        return const EcosystemAccess(hasFleet:true,garages:[
          EcosystemDestination(EcosystemModule.workshop,workspaceId:'shop',name:'Private shop')]);
      }, signOut:() async {}, destinationBuilder:(_) => const SizedBox())));
    await tester.pumpAndSettle();expect(find.text('Private shop'),findsOneWidget);
    fail=true;await tester.tap(find.byKey(const Key('ecosystem_refresh')));
    await tester.pumpAndSettle();expect(find.text('Private shop'),findsNothing);
    expect(find.byKey(const Key('ecosystem_customer')),findsNothing);
    expect(find.textContaining('PRIVATE DATABASE DETAIL'),findsNothing);
    fail=false;await tester.tap(find.byKey(const Key('ecosystem_retry')));
    await tester.pumpAndSettle();expect(find.text('Private shop'),findsOneWidget);
  });
  testWidgets('phone layout supports Polish module picker and failed logout', (tester) async {
    AppLocale.language.value='pl';addTearDown(() => AppLocale.language.value='en');
    tester.view.physicalSize=const Size(360,740);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home:EcosystemGate(
      loadAccess:() async => const EcosystemAccess(hasFleet:false,garages:[]),
      signOut:() async => throw StateError('PRIVATE AUTH DETAIL'),
      destinationBuilder:(_) => const SizedBox())));
    await tester.pumpAndSettle();expect(tester.takeException(),isNull);
    await tester.tap(find.byKey(const Key('ecosystem_logout')));
    await tester.pumpAndSettle();expect(find.textContaining('PRIVATE AUTH DETAIL'),findsNothing);
    expect(find.text('Nie udało się wylogować. Spróbuj ponownie.'),findsOneWidget);
    expect(find.byKey(const Key('ecosystem_customer')),findsOneWidget);
  });
}
