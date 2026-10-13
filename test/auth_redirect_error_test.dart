import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/auth/auth_redirect_error.dart';
import 'package:fleetpilot/auth/auth_link_error_screen.dart';
import 'package:fleetpilot/core/localization.dart';

void main() {
  test('failed callbacks are detected in query and fragment', () {
    expect(hasAuthRedirectError(Uri.parse('https://flotaryx.com/app/#error=access_denied&error_code=otp_expired')), isTrue);
    expect(hasAuthRedirectError(Uri.parse('https://flotaryx.com/app/?error_code=otp_expired')), isTrue);
  });
  test('successful recovery and ordinary billing URLs are unaffected', () {
    expect(hasAuthRedirectError(Uri.parse('https://flotaryx.com/app/#type=recovery&access_token=test-only')), isFalse);
    expect(hasAuthRedirectError(Uri.parse('https://flotaryx.com/app/?billing=success')), isFalse);
    expect(hasAuthRedirectError(Uri.parse('https://flotaryx.com/app/#error=&error_code=')), isFalse);
    expect(hasAuthRedirectError(Uri.parse('https://flotaryx.com/app/#%')), isFalse);
  });
  testWidgets('invalid link offers recovery and preserves return action', (tester) async {
    var returns = 0;
    await tester.pumpWidget(MaterialApp(home: AuthLinkErrorScreen(onContinue: () => returns++)));
    expect(find.text('Link expired or invalid'), findsOneWidget);
    await tester.tap(find.text('Request a new link'));
    await tester.pumpAndSettle();
    expect(find.text('Password recovery'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Return to Flotaryx'));
    expect(returns, 1);
  });
  testWidgets('Polish phone layout shows actionable error without overflow', (tester) async {
    AppLocale.language.value = 'pl';
    addTearDown(() => AppLocale.language.value = 'en');
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: AuthLinkErrorScreen(onContinue: () {})));
    expect(find.text('Link wygasł lub jest nieprawidłowy'), findsOneWidget);
    expect(find.text('Poproś o nowy link'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
