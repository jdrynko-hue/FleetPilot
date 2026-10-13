import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/company/business_review_alert.dart';

void main() {
  Future<void> openAlert(
    WidgetTester tester, {
    required Future<int?> Function() loader,
    Future<void> Function(BuildContext)? openConsole,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              BusinessReviewAlert(
                loadPendingReviews: loader,
                openConsole: openConsole,
                refreshInterval: Duration.zero,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ordinary fleet members never see the operator action',
      (tester) async {
    await openAlert(tester, loader: () async => null);
    expect(find.byKey(const Key('business_review_alert')), findsNothing);
    expect(find.byIcon(Icons.fact_check_outlined), findsNothing);
  });

  testWidgets('pending applications show a badge and open the review console',
      (tester) async {
    var opened = 0;
    await openAlert(
      tester,
      loader: () async => 3,
      openConsole: (_) async { opened++; },
    );
    expect(find.byKey(const Key('business_review_alert')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('business_review_alert')));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('pending count above 100 is not truncated by review list limits',
      (tester) async {
    await openAlert(tester, loader: () async => 135);
    final button = tester.widget<IconButton>(
      find.byKey(const Key('business_review_alert')),
    );
    expect(button.tooltip, contains('135'));
  });

  testWidgets('operators still have access when there are no pending reviews',
      (tester) async {
    await openAlert(tester, loader: () async => 0);
    expect(find.byKey(const Key('business_review_alert')), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('a failed first load must not reveal the operator action',
      (tester) async {
    await openAlert(
      tester,
      loader: () async => throw StateError('Permission denied'),
    );
    expect(find.byKey(const Key('business_review_alert')), findsNothing);
  });
}
