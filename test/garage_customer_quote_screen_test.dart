import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/customer_quote_repository.dart';
import 'package:fleetpilot/garage/customer_quote_screen.dart';
import 'package:fleetpilot/garage/garage_ui_text.dart';

GarageCustomerQuote quote({int revision = 1, bool approved = false}) =>
    GarageCustomerQuoteRepository.parse({
      'revision': revision,
      'currency': 'GBP',
      'subtotal_minor': 6000,
      'tax_minor': 1200,
      'total_minor': 7200,
      'approved': approved,
      'lines': [
        {
          'type': 'labour',
          'description': 'Brake pads and safety inspection',
          'quantity': 2,
          'unit_price_minor': 3000,
          'tax_minor': 1200,
        },
      ],
    })!;

void main() {
  setUp(() => AppLocale.language.value = 'en');
  tearDown(() => AppLocale.language.value = 'en');

  Future<void> display(
    WidgetTester tester, {
    required double width,
    required Future<GarageCustomerQuote?> Function() load,
    required Future<int> Function(int revision) approve,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: GarageCustomerQuoteScreen(
          loadQuote: load,
          approveRevision: approve,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 375.0, 390.0, 900.0]) {
    testWidgets('quote fits narrow and desktop widths: $width',
        (tester) async {
      await display(
        tester,
        width: width,
        load: () async => quote(),
        approve: (revision) async => revision,
      );
      expect(find.byKey(const Key('garage_quote_revision')), findsOneWidget);
      expect(find.text('£72.00'), findsWidgets);
      expect(find.byKey(const Key('garage_quote_approve')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('requires explicit confirmation and can be cancelled',
      (tester) async {
    var approvals = 0;
    await display(
      tester,
      width: 375,
      load: () async => quote(),
      approve: (revision) async {
        approvals += 1;
        return revision;
      },
    );
    await tester.tap(find.byKey(const Key('garage_quote_approve')));
    await tester.pumpAndSettle();
    expect(find.textContaining('revision 1'), findsOneWidget);
    expect(approvals, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(approvals, 0);
  });

  testWidgets('checks for changes before sending approval',
      (tester) async {
    var loads = 0;
    var approvals = 0;
    await display(
      tester,
      width: 390,
      load: () async {
        loads += 1;
        return quote(revision: loads == 1 ? 1 : 2);
      },
      approve: (revision) async {
        approvals += 1;
        return revision;
      },
    );
    await tester.tap(find.byKey(const Key('garage_quote_approve')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('garage_quote_confirm')));
    await tester.pumpAndSettle();
    expect(approvals, 0);
    expect(find.text('Revision 2'), findsOneWidget);
    expect(find.textContaining('The estimate changed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a confirmed approval stops the button being reusable',
      (tester) async {
    var count = 0;
    var approved = false;
    await display(
      tester,
      width: 375,
      load: () async => quote(approved: approved),
      approve: (revision) async {
        count += 1;
        approved = true;
        return revision;
      },
    );
    await tester.tap(find.byKey(const Key('garage_quote_approve')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('garage_quote_confirm')));
    await tester.pumpAndSettle();
    expect(count, 1);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('garage_quote_approve')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Approved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('successful RPC blocks duplicate approval even if read is stale',
      (tester) async {
    var approvals = 0;
    await display(
      tester,
      width: 375,
      load: () async => quote(approved: false),
      approve: (revision) async {
        approvals++;
        return revision;
      },
    );
    await tester.tap(find.byKey(const Key('garage_quote_approve')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('garage_quote_confirm')));
    await tester.pumpAndSettle();
    expect(approvals, 1);
    await tester.tap(find.byKey(const Key('garage_quote_refresh')));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('garage_quote_approve')),
    );
    expect(button.onPressed, isNull);
    expect(approvals, 1);
  });

  testWidgets('failed approval does not leave a stale actionable estimate',
      (tester) async {
    await display(
      tester,
      width: 390,
      load: () async => quote(),
      approve: (_) async => throw StateError('Server rejected stale version'),
    );
    await tester.tap(find.byKey(const Key('garage_quote_approve')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('garage_quote_confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('garage_quote_empty')), findsOneWidget);
    expect(find.byKey(const Key('garage_quote_approve')), findsNothing);
    expect(find.textContaining('Refresh the estimate'), findsOneWidget);
  });

  testWidgets('already approved quote has no active confirmation',
      (tester) async {
    await display(
      tester,
      width: 320,
      load: () async => quote(approved: true),
      approve: (revision) async => revision,
    );
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('garage_quote_approve')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Approved'), findsOneWidget);
  });

  testWidgets('PL quote view shows amount and revision',
      (tester) async {
    AppLocale.language.value = 'pl';
    await display(
      tester,
      width: 375,
      load: () async => quote(),
      approve: (revision) async => revision,
    );
    expect(find.text('Wycena naprawy'), findsOneWidget);
    expect(find.text('Wersja 1'), findsOneWidget);
    expect(find.text('Oczekuje na zgodę'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed quote load has retry without stale previous data',
      (tester) async {
    await display(
      tester,
      width: 320,
      load: () async => throw StateError('Forbidden'),
      approve: (revision) async => revision,
    );
    expect(find.byKey(const Key('garage_quote_empty')), findsOneWidget);
    expect(find.byKey(const Key('garage_quote_approve')), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('quote-approval labels and revision/amount placeholders exist in 12 languages', () {
    for (final language in supportedLanguages) {
      for (final key in [
        'customerEstimateTitle', 'customerApprove', 'customerConfirm',
        'customerCancel', 'customerLoadFailed', 'customerChanged',
        'customerRecorded', 'customerApprovedMessage',
        'customerApprovalUncertain', 'customerEmpty', 'customerRetry',
        'customerApproved', 'customerPending', 'customerTax',
        'customerSubtotal', 'customerTotalTax', 'customerTotal',
        'customerApproving', 'customerScopeWarning',
      ]) {
        final label = GarageUiText.get(key, language: language);
        expect(label.trim(), isNotEmpty, reason: '$language $key');
        expect(label, isNot(key), reason: '$language $key');
      }
      final confirm = GarageUiText.format('customerConfirmBody',
        {'revision': 7, 'total': 'GBP 72.00'}, language: language);
      expect(confirm, contains('7'), reason: language);
      expect(confirm, contains('GBP 72.00'), reason: language);
      expect(confirm, isNot(contains('{revision}')), reason: language);
      expect(confirm, isNot(contains('{total}')), reason: language);
      expect(GarageUiText.format('customerRevision', {'revision': 7},
        language: language), contains('7'), reason: language);
    }
  });

  testWidgets('German mobile approval dialog retains revision and sum',
      (tester) async {
    AppLocale.language.value = 'de';
    var approvals = 0;
    await display(
      tester, width: 390,
      load: () async => quote(),
      approve: (revision) async { approvals++; return revision; },
    );
    expect(find.text('Reparaturkostenvoranschlag'), findsOneWidget);
    expect(find.text('Version 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('garage_quote_approve')));
    await tester.pumpAndSettle();
    expect(find.text('Kostenvoranschlag bestätigen'), findsOneWidget);
    expect(find.textContaining('£72.00'), findsWidgets);
    expect(approvals, 0);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(approvals, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Spanish mobile quote retains fail-closed stale revision check',
      (tester) async {
    AppLocale.language.value = 'es';
    var loads = 0;
    var approvals = 0;
    await display(
      tester, width: 375,
      load: () async => quote(revision: ++loads == 1 ? 1 : 2),
      approve: (revision) async { approvals++; return revision; },
    );
    expect(find.text('Presupuesto de reparación'), findsOneWidget);
    await tester.tap(find.byKey(const Key('garage_quote_approve')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('garage_quote_confirm')));
    await tester.pumpAndSettle();
    expect(approvals, 0);
    expect(find.text('Versión 2'), findsOneWidget);
    expect(find.textContaining('El presupuesto ha cambiado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });


  testWidgets('old scope request never overwrites newly selected order',
      (tester) async {
    final previous = Completer<GarageCustomerQuote?>();
    final oldLoad = () => previous.future;
    final newLoad = () async => quote(revision: 2);
    final approve = (int revision) async => revision;
    await tester.pumpWidget(MaterialApp(home: GarageCustomerQuoteScreen(
      loadQuote: oldLoad, approveRevision: approve,
    )));
    await tester.pump();
    await tester.pumpWidget(MaterialApp(home: GarageCustomerQuoteScreen(
      loadQuote: newLoad, approveRevision: approve,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Revision 2'), findsOneWidget);
    previous.complete(quote(revision: 1));
    await tester.pumpAndSettle();
    expect(find.text('Revision 2'), findsOneWidget);
    expect(find.text('Revision 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('approved revision marker is never shared across scopes',
      (tester) async {
    final approve = (int revision) async => revision;
    await tester.pumpWidget(MaterialApp(home: GarageCustomerQuoteScreen(
      loadQuote: () async => quote(approved: true), approveRevision: approve,
    )));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(
      find.byKey(const Key('garage_quote_approve'))).onPressed, isNull);
    await tester.pumpWidget(MaterialApp(home: GarageCustomerQuoteScreen(
      loadQuote: () async => quote(approved: false), approveRevision: approve,
    )));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(
      find.byKey(const Key('garage_quote_approve'))).onPressed, isNotNull);
    expect(find.text('Awaiting approval'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scope switch while approval dialog is open cannot call old RPC',
      (tester) async {
    var previousApprovals = 0;
    var newApprovals = 0;
    final oldLoad = () async => quote();
    final newLoad = () async => quote(revision: 2);
    await tester.pumpWidget(MaterialApp(home: GarageCustomerQuoteScreen(
      loadQuote: oldLoad,
      approveRevision: (revision) async { previousApprovals++; return revision; },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('garage_quote_approve')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(MaterialApp(home: GarageCustomerQuoteScreen(
      loadQuote: newLoad,
      approveRevision: (revision) async { newApprovals++; return revision; },
    )));
    await tester.pump();
    await tester.tap(find.byKey(const Key('garage_quote_confirm')));
    await tester.pumpAndSettle();
    expect(previousApprovals, 0);
    expect(newApprovals, 0);
    expect(find.text('Revision 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
